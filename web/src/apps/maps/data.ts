import { t } from '@/i18n';
import { newId as libNewId } from '@/lib/format';
import { readJson, writeJson } from '@/lib/storage';
import { ICON_KEYS } from '@/lib/waypointCode';

/**
 * The phone must use the same simple CRS as the other Everfall maps. Keep
 * these coordinates private to the renderer; every public phone contract
 * continues to exchange GTA world `{ x, y }` values.
 */
export const MAP_CENTER: [number, number] = [-119.43, 58.84];
export const MAP_SCALE = 1.421 / 100;
export const MAP_BOUNDS = { north: 0, south: -192, west: 0, east: 128 };
export const MAP_WIDTH = MAP_BOUNDS.east - MAP_BOUNDS.west;
export const MAP_HEIGHT = MAP_BOUNDS.north - MAP_BOUNDS.south;
export const TILE_SIZE = 256;
export const MIN_TILE_ZOOM = 2;
export const MAX_TILE_ZOOM = 7;

export function gameToMap(x: number, y: number): [number, number] {
    return [MAP_CENTER[0] + MAP_SCALE * y, MAP_CENTER[1] + MAP_SCALE * x];
}

export function mapToGame(latitude: number, longitude: number): { x: number; y: number } {
    return {
        x: (longitude - MAP_CENTER[1]) / MAP_SCALE,
        y: (latitude - MAP_CENTER[0]) / MAP_SCALE,
    };
}

export const WORLD = {
    xMin: (MAP_BOUNDS.west - MAP_CENTER[1]) / MAP_SCALE,
    xMax: (MAP_BOUNDS.east - MAP_CENTER[1]) / MAP_SCALE,
    yMin: (MAP_BOUNDS.south - MAP_CENTER[0]) / MAP_SCALE,
    yMax: (MAP_BOUNDS.north - MAP_CENTER[0]) / MAP_SCALE,
};

export function projectPct(x: number, y: number) {
    const [latitude, longitude] = gameToMap(x, y);
    return {
        left: ((longitude - MAP_BOUNDS.west) / MAP_WIDTH) * 100,
        top:  ((MAP_BOUNDS.north - latitude) / MAP_HEIGHT) * 100,
    };
}

export function pctToWorld(leftPct: number, topPct: number) {
    const longitude = MAP_BOUNDS.west + (leftPct / 100) * MAP_WIDTH;
    const latitude = MAP_BOUNDS.north - (topPct / 100) * MAP_HEIGHT;
    return mapToGame(latitude, longitude);
}

export function mapTileGrid(z: number): { columns: number; rows: number } {
    const scale = 2 ** z;
    return {
        columns: Math.ceil((MAP_WIDTH * scale) / TILE_SIZE),
        rows: Math.ceil((MAP_HEIGHT * scale) / TILE_SIZE),
    };
}

export function newId(): string {
    return libNewId('m');
}

export function initials(name: string): string {
    const parts = name.trim().split(/\s+/).filter(Boolean);
    if (parts.length === 0) return '?';
    if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

export function timeAgo(ms?: number): string {
    if (!ms) return t('maps.offline', 'offline');
    const s = Math.max(0, Math.floor((Date.now() - ms) / 1000));
    if (s < 15) return t('maps.now', 'now');
    if (s < 60) return t('maps.secondsAgo', '{s}s ago', { s });
    const m = Math.floor(s / 60);
    if (m < 60) return t('maps.minutesAgo', '{m}m ago', { m });
    return t('maps.hoursAgo', '{h}h ago', { h: Math.floor(m / 60) });
}


export type MapStyleId = 'everfall';
export type MapTileStyle = 'everfall';

export interface TileSource {
    base:    string;
    ext:     'png';
    maxZoom: number;
    px:      number;
}

const TILE_BASE = 'https://files.coolgingerginger.me/tiles';

export const TILE_SOURCES: Record<MapTileStyle, TileSource> = {
    everfall: { base: TILE_BASE, ext: 'png', maxZoom: MAX_TILE_ZOOM, px: TILE_SIZE },
};

export const MAX_NATIVE_PX = MAP_WIDTH * 2 ** MAX_TILE_ZOOM;
export const MAX_NATIVE_PY = MAP_HEIGHT * 2 ** MAX_TILE_ZOOM;

export interface MapStyle {
    id:     MapStyleId;
    label:  string;
    tiles:  MapTileStyle;
    filter: string;
    wash?:  string;
    bg:     string;
}

export const MAP_STYLE: MapStyle = {
    id: 'everfall',
    label: t('maps.styleEverfall', 'Everfall map'),
    tiles: 'everfall',
    filter: 'none',
    bg: '#0b2838',
};

export function tileUrl(tiles: MapTileStyle, z: number, x: number, y: number): string {
    const s = TILE_SOURCES[tiles];
    return `${s.base}/${z}/${x}/${y}.${s.ext}`;
}

export function styleMaxZoom(tiles: MapTileStyle): number {
    return TILE_SOURCES[tiles].maxZoom;
}

export function stylePx(tiles: MapTileStyle): number {
    return TILE_SOURCES[tiles].px;
}


export interface MapMarker {
    id:    string;
    label: string;
    x:     number;
    y:     number;
    color: string;
    icon:  string;
}

export const COLOR_SWATCHES = [
    '#f0c43a', '#5c6cf3', '#f5a242', '#3dd2bb', '#e573e1', '#7adcff',
    '#e53e57', '#a78bfa', '#22c55e', '#fb7185', '#06b6d4', '#84cc16',
];

export { ICON_KEYS };
export type IconKey = (typeof ICON_KEYS)[number];

const STORE_KEY = 'sd-phone:maps:v1';

export function loadMarkers(): MapMarker[] {
    return readJson<MapMarker[]>(STORE_KEY, Array.isArray) ?? getDefaultMarkers();
}

export function saveMarkers(markers: MapMarker[]): void {
    writeJson(STORE_KEY, markers);
}

export function getDefaultMarkers(): MapMarker[] {
    return [
        { id: 'seed-home', label: t('maps.seedHome', 'Home'),     x: -1037, y: -2738, color: '#3dd2bb', icon: 'Home' },
        { id: 'seed-gar',  label: t('maps.seedMechanic', 'Mechanic'), x:  -337, y: -136,  color: '#f5a242', icon: 'Wrench' },
    ];
}
