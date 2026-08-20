import {
    createContext, forwardRef, memo, useCallback, useContext, useEffect,
    useImperativeHandle, useLayoutEffect, useMemo, useRef, useState,
} from 'react';
import type { ReactNode } from 'react';
import { Locate, Minus, Plus } from 'lucide-react';

import { MAP_HEIGHT, MAP_STYLE, MAP_WIDTH, MAX_NATIVE_PX, MAX_NATIVE_PY, MIN_TILE_ZOOM, mapTileGrid, pctToWorld, projectPct, styleMaxZoom, tileUrl } from './data';
import type { MapStyle } from './data';
import { t } from '@/i18n';

const MIN_SCALE = 1;
const OVERZOOM = 0.7;
function maxScaleFor(width: number, height: number): number {
    if (!width || !height) return 16;
    return Math.max(
        MIN_SCALE + 2,
        Math.min(MAX_NATIVE_PX / width, MAX_NATIVE_PY / height) * OVERZOOM,
    );
}

function maxLevelFor(width: number, height: number): number {
    return Math.max(MIN_TILE_ZOOM, Math.floor(Math.log2(maxScaleFor(width, height))));
}
function snapLevel(level: number, width: number, height: number): number {
    return 2 ** Math.max(0, Math.min(maxLevelFor(width, height), Math.round(level)));
}

function ancestorZoom(el: HTMLElement | null): number {
    let z = 1;
    for (let n: HTMLElement | null = el; n; n = n.parentElement) {
        const cz = parseFloat(getComputedStyle(n).getPropertyValue('zoom'));
        if (cz > 0 && cz !== 1) z *= cz;
    }
    return z || 1;
}

interface MapTransform { scale: number; tx: number; ty: number; width: number; height: number; vw: number; vh: number; pow: number; gesturing: boolean }
const MapTransformContext = createContext<MapTransform>({ scale: 1, tx: 0, ty: 0, width: 0, height: 0, vw: 0, vh: 0, pow: 1, gesturing: false });

export function usePinStyle(x: number, y: number): React.CSSProperties {
    const { scale, tx, ty, width, height, vw, vh, gesturing } = useContext(MapTransformContext);
    const pct = projectPct(x, y);
    const left = vw / 2 + ((pct.left / 100) * width - width / 2) * scale + tx;
    const top  = vh / 2 + ((pct.top  / 100) * height - height / 2) * scale + ty;
    return {
        position: 'absolute', left, top, transform: 'translate(-50%, -50%)',
        transition: gesturing
            ? 'none'
            : 'left 200ms cubic-bezier(0.22,0.61,0.36,1), top 200ms cubic-bezier(0.22,0.61,0.36,1)',
    };
}

export function useStageProjector(): (x: number, y: number) => { x: number; y: number } {
    const { width, height, pow } = useContext(MapTransformContext);
    const widthP = width * pow;
    const heightP = height * pow;
    return useCallback((x: number, y: number) => {
        const pct = projectPct(x, y);
        return { x: (pct.left / 100) * widthP, y: (pct.top / 100) * heightP };
    }, [widthP, heightP]);
}

export interface MapViewHandle {
    centerOnWorld: (x: number, y: number, minZoom?: number) => void;
    fitWorld: (pts: { x: number; y: number }[], padFrac?: number) => void;
    reset: () => void;
}

interface MapViewProps {
    children?:   ReactNode;
    placing?:    boolean;
    onPlace?:    (x: number, y: number, anchor: { ax: number; ay: number; fx: number; fy: number }) => void;
    onTapEmpty?: () => void;
    overlay?:    ReactNode;
    stageOverlay?: ReactNode;
    fit?:        boolean;
    fitTo?:      { x: number; y: number }[];
    centerTo?:   { x: number; y: number };
    chrome?:       boolean;
    chromeTop?:    string;
    chromeBottom?: string;
    insetBottom?: number;
    insetTop?:    number;
}

export const MapView = forwardRef<MapViewHandle, MapViewProps>(function MapView(
    { children, placing = false, onPlace, onTapEmpty, overlay, stageOverlay, fit = false, fitTo, centerTo, chrome = true, chromeTop, chromeBottom, insetBottom = 0, insetTop = 0 }, ref,
) {
    const viewportRef = useRef<HTMLDivElement | null>(null);
    const stageRef    = useRef<HTMLDivElement | null>(null);

    const [scale, setScale] = useState(1);
    const [tx, setTx] = useState(0);
    const [ty, setTy] = useState(0);
    const viewRef = useRef({ scale: 1, tx: 0, ty: 0 });
    viewRef.current.scale = scale;
    viewRef.current.tx = tx;
    viewRef.current.ty = ty;
    const [vw, setVw] = useState(0);
    const [vh, setVh] = useState(0);
    const [dragging, setDragging] = useState(false);
    const [pinching, setPinching] = useState(false);
    const mapAspect = MAP_WIDTH / MAP_HEIGHT;
    const height = fit
        ? Math.min(vh, vw / mapAspect)
        : Math.max(vh, vw / mapAspect);
    const width = height * mapAspect;
    const style = MAP_STYLE;

    useLayoutEffect(() => {
        const el = viewportRef.current;
        if (!el) return;
        const measure = () => { setVw(el.clientWidth); setVh(el.clientHeight); };
        measure();
        const ro = new ResizeObserver(measure);
        ro.observe(el);
        return () => ro.disconnect();
    }, []);

    const minScale = width && height
        ? Math.min(1, vw / (width * 0.72), vh / (height * 0.72))
        : 1;

    const stepScale = (dir: 1 | -1): number => {
        const lvl = Math.log2(viewRef.current.scale);
        if (dir > 0) {
            const up = Math.floor(lvl + 1e-6) + 1;
            return up <= 0 ? 1 : 2 ** Math.min(maxLevelFor(width, height), up);
        }
        const down = Math.ceil(lvl - 1e-6) - 1;
        return down < 0 ? minScale : 2 ** down;
    };

    const clampPan = useCallback((nx: number, ny: number, s: number) => {
        const vp = viewportRef.current;
        const W = vp?.clientWidth ?? 0;
        const H = vp?.clientHeight ?? 0;
        const scaledWidth = width * s;
        const scaledHeight = height * s;
        const maxX = Math.max(0, (scaledWidth - W) / 2);
        const maxY = Math.max(0, (scaledHeight - H) / 2);
        return {
            x: Math.max(-maxX, Math.min(maxX, nx)),
            y: Math.max(-(maxY + insetBottom), Math.min(maxY + insetTop, ny)),
        };
    }, [width, height, insetBottom, insetTop]);

    const zoomAround = useCallback((clientX: number, clientY: number, nextScale: number) => {
        const vp = viewportRef.current;
        if (!vp) return;
        const rect = vp.getBoundingClientRect();
        const z = ancestorZoom(vp);
        const cx = (clientX / z - rect.left) - vw / 2;
        const cy = (clientY / z - rect.top)  - vh / 2;
        const view = viewRef.current;
        const s = Math.max(minScale, Math.min(maxScaleFor(width, height), nextScale));
        if (s === view.scale) return;
        const ratio = s / view.scale;
        const c = clampPan(cx - (cx - view.tx) * ratio, cy - (cy - view.ty) * ratio, s);
        viewRef.current = { scale: s, tx: c.x, ty: c.y };
        setScale(s); setTx(c.x); setTy(c.y);
    }, [clampPan, vw, vh, minScale, width, height]);

    const lastWheelStep = useRef(0);

    const wheelRef = useRef<(e: WheelEvent) => void>(() => {});
    wheelRef.current = (e: WheelEvent) => {
        e.preventDefault();
        const now = performance.now();
        if (now - lastWheelStep.current < 160) return;
        lastWheelStep.current = now;
        zoomAround(e.clientX, e.clientY, stepScale(e.deltaY < 0 ? 1 : -1));
    };

    useEffect(() => {
        const el = viewportRef.current;
        if (!el) return;
        const onWheel = (e: WheelEvent) => wheelRef.current(e);
        el.addEventListener('wheel', onWheel, { passive: false });
        return () => el.removeEventListener('wheel', onWheel);
    }, []);
    function buttonZoom(dir: 1 | -1) {
        const vp = viewportRef.current;
        if (!vp) return;
        const rect = vp.getBoundingClientRect();
        const z = ancestorZoom(vp);
        zoomAround((rect.left + rect.width / 2) * z, (rect.top + rect.height / 2) * z, stepScale(dir));
    }
    function resetView() { setScale(1); setTx(0); setTy(0); }

    const centerOnWorld = useCallback((x: number, y: number, minZoom = 2.4) => {
        const pct = projectPct(x, y);
        const s = snapLevel(Math.log2(Math.max(scale, minZoom)), width, height);
        const ox = (pct.left / 100 - 0.5) * width;
        const oy = (pct.top  / 100 - 0.5) * height;
        const c = clampPan(-ox * s, -oy * s, s);
        setScale(s); setTx(c.x); setTy(c.y);
    }, [scale, width, height, clampPan]);

    const fitWorld = useCallback((pts: { x: number; y: number }[], padFrac = 0.16) => {
        if (!pts.length || !width || !height || !vw || !vh) return;
        const ps = pts.map(p => projectPct(p.x, p.y));
        const minL = Math.min(...ps.map(p => p.left)), maxL = Math.max(...ps.map(p => p.left));
        const minT = Math.min(...ps.map(p => p.top)),  maxT = Math.max(...ps.map(p => p.top));
        const midL = (minL + maxL) / 2, midT = (minT + maxT) / 2;
        const spanX = Math.max(1, ((maxL - minL) / 100) * width);
        const spanY = Math.max(1, ((maxT - minT) / 100) * height);
        const target = Math.min((vw * (1 - 2 * padFrac)) / spanX, (vh * (1 - 2 * padFrac)) / spanY);
        const s = target < 1
            ? minScale
            : Math.max(minScale, Math.min(maxScaleFor(width, height), 2 ** Math.min(maxLevelFor(width, height), Math.floor(Math.log2(target) + 1e-6))));
        const ox = (midL / 100 - 0.5) * width;
        const oy = (midT / 100 - 0.5) * height;
        const c = clampPan(-ox * s, -oy * s, s);
        setScale(s); setTx(c.x); setTy(c.y);
    }, [width, height, vw, vh, minScale, clampPan]);

    useImperativeHandle(ref, () => ({ centerOnWorld, fitWorld, reset: resetView }), [centerOnWorld, fitWorld]);

    const didFit = useRef(false);
    useLayoutEffect(() => { didFit.current = false; }, [fitTo]);
    useLayoutEffect(() => {
        if (didFit.current || !fitTo || !fitTo.length || !width || !height || !vw || !vh) return;
        didFit.current = true;
        fitWorld(fitTo);
    }, [fitTo, width, height, vw, vh, fitWorld]);

    const didCenter = useRef(false);
    useLayoutEffect(() => { didCenter.current = false; }, [centerTo]);
    useLayoutEffect(() => {
        if (didCenter.current || !centerTo || !width || !height || !vw || !vh) return;
        didCenter.current = true;
        centerOnWorld(centerTo.x, centerTo.y);
    }, [centerTo, width, height, vw, vh, centerOnWorld]);

    const pointers = useRef<Map<number, { x: number; y: number }>>(new Map());
    const gesture  = useRef({ startX: 0, startY: 0, tx: 0, ty: 0, moved: 0, pinchDist: 0, pinchScale: 1, z: 1 });

    const panRaf     = useRef<number | null>(null);
    const pendingPan = useRef<{ x: number; y: number } | null>(null);
    const flushPan = useCallback(() => {
        panRaf.current = null;
        const p = pendingPan.current;
        if (p) { setTx(p.x); setTy(p.y); }
    }, []);
    const queuePan = useCallback((x: number, y: number) => {
        pendingPan.current = { x, y };
        if (panRaf.current === null) panRaf.current = requestAnimationFrame(flushPan);
    }, [flushPan]);
    useEffect(() => () => { if (panRaf.current !== null) cancelAnimationFrame(panRaf.current); }, []);

    const zoomRaf     = useRef<number | null>(null);
    const pendingZoom = useRef<{ cx: number; cy: number; scale: number } | null>(null);
    const flushZoom = useCallback(() => {
        zoomRaf.current = null;
        const p = pendingZoom.current;
        pendingZoom.current = null;
        if (p) zoomAround(p.cx, p.cy, p.scale);
    }, [zoomAround]);
    const queueZoom = useCallback((cx: number, cy: number, targetScale: number) => {
        pendingZoom.current = { cx, cy, scale: targetScale };
        if (zoomRaf.current === null) zoomRaf.current = requestAnimationFrame(flushZoom);
    }, [flushZoom]);
    useEffect(() => () => {
        if (zoomRaf.current !== null) cancelAnimationFrame(zoomRaf.current);
    }, []);

    function onPointerDown(e: React.PointerEvent) {
        (e.target as Element).setPointerCapture?.(e.pointerId);
        pointers.current.set(e.pointerId, { x: e.clientX, y: e.clientY });
        if (pointers.current.size === 1) {
            setDragging(true);
            const z = ancestorZoom(viewportRef.current);
            gesture.current = { ...gesture.current, startX: e.clientX, startY: e.clientY, tx, ty, moved: 0, z };
        } else if (pointers.current.size === 2) {
            const [a, b] = [...pointers.current.values()];
            gesture.current.pinchDist  = Math.hypot(a.x - b.x, a.y - b.y);
            gesture.current.pinchScale = scale;
            setPinching(true);
        }
    }
    function onPointerMove(e: React.PointerEvent) {
        if (!pointers.current.has(e.pointerId)) return;
        pointers.current.set(e.pointerId, { x: e.clientX, y: e.clientY });
        if (pointers.current.size >= 2) {
            const [a, b] = [...pointers.current.values()];
            const dist = Math.hypot(a.x - b.x, a.y - b.y);
            if (gesture.current.pinchDist > 0) {
                queueZoom((a.x + b.x) / 2, (a.y + b.y) / 2, gesture.current.pinchScale * (dist / gesture.current.pinchDist));
            }
            gesture.current.moved += 99;
            return;
        }
        if (!dragging) return;
        const rawDx = e.clientX - gesture.current.startX;
        const rawDy = e.clientY - gesture.current.startY;
        gesture.current.moved = Math.max(gesture.current.moved, Math.hypot(rawDx, rawDy));
        const z = gesture.current.z || 1;
        const c = clampPan(gesture.current.tx + rawDx / z, gesture.current.ty + rawDy / z, scale);
        queuePan(c.x, c.y);
    }
    function onPointerUp(e: React.PointerEvent) {
        if (panRaf.current !== null) { cancelAnimationFrame(panRaf.current); panRaf.current = null; }
        if (pendingPan.current) { setTx(pendingPan.current.x); setTy(pendingPan.current.y); pendingPan.current = null; }
        const wasTap = gesture.current.moved < 6 && pointers.current.size === 1;
        const wasPinch = pointers.current.size === 2;
        pointers.current.delete(e.pointerId);
        if (pointers.current.size === 0) setDragging(false);

        if (wasPinch) {
            gesture.current.pinchDist = 0;
            setPinching(false);
            const vp = viewportRef.current;
            if (vp) {
                const rect = vp.getBoundingClientRect();
                const az = ancestorZoom(vp);
                const live = pendingZoom.current?.scale ?? scale;
                const snapped = live <= Math.sqrt(minScale)
                    ? minScale
                    : snapLevel(Math.log2(live), width, height);
                zoomAround((rect.left + rect.width / 2) * az, (rect.top + rect.height / 2) * az, snapped);
            }
            const rest = [...pointers.current.values()][0];
            if (rest) {
                gesture.current = { ...gesture.current, startX: rest.x, startY: rest.y, tx, ty };
            }
        }
        if (wasTap && placing && onPlace) {
            const vp = viewportRef.current;
            if (!vp || !vp.clientWidth) return;
            const vpRect = vp.getBoundingClientRect();
            const z = ancestorZoom(vp);
            const localX = e.clientX / z - vpRect.left;
            const localY = e.clientY / z - vpRect.top;
            const rawL = (((localX - vw / 2 - tx) / scale + width / 2) / width) * 100;
            const rawT = (((localY - vh / 2 - ty) / scale + height / 2) / height) * 100;
            const leftPct = Math.max(0, Math.min(100, rawL));
            const topPct  = Math.max(0, Math.min(100, rawT));
            const w = pctToWorld(leftPct, topPct);
            onPlace(w.x, w.y, { ax: localX, ay: localY, fx: leftPct / 100, fy: topPct / 100 });
        } else if (wasTap) {
            onTapEmpty?.();
        }
    }

    useEffect(() => {
        const c = clampPan(tx, ty, scale);
        if (c.x !== tx) setTx(c.x);
        if (c.y !== ty) setTy(c.y);
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [width, height, insetBottom, insetTop]);

    const powRef = useRef(1);
    if (!pinching || powRef.current < 1) {
        powRef.current = 2 ** Math.max(0, Math.min(6, Math.round(Math.log2(Math.max(1, scale)))));
    }
    const pow = powRef.current;
    const stageWidth = width * pow;
    const stageHeight = height * pow;

    const transform: MapTransform = { scale, tx, ty, width, height, vw, vh, pow, gesturing: dragging || pinching };

    const painted = useRef<{ scale: number; tx: number; ty: number; pow: number } | null>(null);
    const glide = useRef<Animation | null>(null);
    useLayoutEffect(() => {
        const el = stageRef.current;
        const prev = painted.current;
        painted.current = { scale, tx, ty, pow };
        if (!el || !prev) return;
        if (dragging || pinching) return;
        if (prev.scale === scale && prev.tx === tx && prev.ty === ty && prev.pow === pow) return;

        let from: string;
        const running = glide.current?.playState === 'running';
        if (running) {
            const m = new DOMMatrix(getComputedStyle(el).transform);
            from = `translate(${m.e}px, ${m.f}px) scale(${(m.a * prev.pow) / pow})`;
        } else {
            from = `translate(${prev.tx}px, ${prev.ty}px) scale(${prev.scale / pow})`;
        }
        glide.current?.cancel();
        glide.current = el.animate(
            [{ transform: from }, { transform: `translate(${tx}px, ${ty}px) scale(${scale / pow})` }],
            { duration: 200, easing: 'cubic-bezier(0.22,0.61,0.36,1)' },
        );
    }, [scale, tx, ty, pow, dragging, pinching]);

    return (
        <div
            ref={viewportRef}
            className="relative h-full w-full touch-none overflow-hidden"
            style={{ background: style.bg, transition: 'background 400ms ease', cursor: dragging ? 'grabbing' : placing ? 'crosshair' : 'grab' }}
            onPointerDown={onPointerDown}
            onPointerMove={onPointerMove}
            onPointerUp={onPointerUp}
            onPointerCancel={onPointerUp}
        >
            <div
                ref={stageRef}
                className="absolute"
                style={{
                    width: stageWidth, height: stageHeight,
                    left: (vw - stageWidth) / 2,
                    top:  (vh - stageHeight) / 2,
                    transform: `translate(${tx}px, ${ty}px) scale(${scale / pow})`,
                    transformOrigin: 'center',
                    willChange: 'transform',
                }}
            >
                <div className="absolute inset-0" style={{ background: style.bg }} />
                <div className="absolute inset-0">
                    <TileGrid style={style} width={width} height={height} pow={pow} scale={scale} tx={Math.round(tx / 64) * 64} ty={Math.round(ty / 64) * 64} vpW={vw} vpH={vh} />
                </div>
                {style.wash && (
                    <div className="absolute inset-0" style={{ background: style.wash, pointerEvents: 'none' }} />
                )}
                {stageOverlay && (
                    <div className="pointer-events-none absolute inset-0">
                        <MapTransformContext.Provider value={transform}>
                            {stageOverlay}
                        </MapTransformContext.Provider>
                    </div>
                )}
            </div>

            <div className="pointer-events-none absolute inset-0 z-10">
                <MapTransformContext.Provider value={transform}>
                    {children}
                </MapTransformContext.Provider>
            </div>

            {chrome && (
            <div
                className="absolute right-3 z-30 flex flex-col items-end gap-2"
                style={{ top: chromeTop ?? '12px' }}
                onPointerDown={e => e.stopPropagation()}
                onPointerMove={e => e.stopPropagation()}
                onPointerUp={e => e.stopPropagation()}
                onWheel={e => e.stopPropagation()}
            >
                <div className="flex flex-col overflow-hidden rounded-[10px] bg-elevated/90 shadow-md ring-1 ring-black/5 dark:bg-elevated/90 dark:ring-white/10">
                    <CtrlBtn onClick={() => buttonZoom(1)} label={t('maps.zoomIn', 'Zoom in')}><Plus className="h-[18px] w-[18px]" /></CtrlBtn>
                    <div className="h-px w-full bg-black/10 dark:bg-white/10" />
                    <CtrlBtn onClick={() => buttonZoom(-1)} label={t('maps.zoomOut', 'Zoom out')}><Minus className="h-[18px] w-[18px]" /></CtrlBtn>
                </div>
                <button
                    onClick={resetView}
                    aria-label={t('maps.fitMap', 'Fit map')}
                    className="flex h-9 w-9 items-center justify-center rounded-[10px] bg-elevated/90 text-ios-blue shadow-md ring-1 ring-black/5 dark:bg-elevated/90 dark:ring-white/10"
                >
                    <Locate className="h-[18px] w-[18px]" />
                </button>
            </div>
            )}

            {chrome && (
            <div className="absolute left-3 z-20 rounded-full bg-black/60 px-2.5 py-1 text-[12px] font-bold tracking-[0.06em] text-white/95" style={{ bottom: chromeBottom ?? '12px', transition: 'bottom 300ms cubic-bezier(0.22,0.61,0.36,1)' }}>
                {Math.round(scale * 100)}%
            </div>
            )}

            {overlay}
        </div>
    );
});

const BACKDROP_Z = MIN_TILE_ZOOM;

const DEBUG_TILES = (() => { try { return localStorage.getItem('sd-phone:maps:debug') === '1'; } catch { return false; } })();
const DBG_COLOR: Record<number, string> = { 2: '#ff0000', 3: '#ff8800', 4: '#00ff00', 5: '#00ffff', 6: '#ff00ff', 7: '#ffff00' };

function tileLayer(
    style: MapStyle, z: number, width: number, height: number, scale: number, tx: number, ty: number,
    vpW: number, vpH: number, keyPrefix: string, fullGrid: boolean,
): ReactNode[] {
    const grid = mapTileGrid(z);
    const tileWidth = width / grid.columns;
    const tileHeight = height / grid.rows;
    const clampX = (v: number) => Math.max(0, Math.min(grid.columns - 1, v));
    const clampY = (v: number) => Math.max(0, Math.min(grid.rows - 1, v));

    let iMin = 0, iMax = grid.columns - 1, jMin = 0, jMax = grid.rows - 1;
    if (!fullGrid) {
        const qx0 = (-vpW / 2 - tx) / scale + width / 2;
        const qx1 = ( vpW / 2 - tx) / scale + width / 2;
        const qy0 = (-vpH / 2 - ty) / scale + height / 2;
        const qy1 = ( vpH / 2 - ty) / scale + height / 2;
        const marginX = 1 + Math.round(32 / Math.max(1, tileWidth * scale));
        const marginY = 1 + Math.round(32 / Math.max(1, tileHeight * scale));
        iMin = clampX(Math.floor(qx0 / tileWidth) - marginX); iMax = clampX(Math.floor(qx1 / tileWidth) + marginX);
        jMin = clampY(Math.floor(qy0 / tileHeight) - marginY); jMax = clampY(Math.floor(qy1 / tileHeight) + marginY);
    }

    const dbg = DEBUG_TILES ? (DBG_COLOR[z] ?? '#ffffff') : undefined;
    const seam = 0.6 / Math.max(1, scale);
    const tiles: ReactNode[] = [];
    for (let j = jMin; j <= jMax; j++) {
        for (let i = iMin; i <= iMax; i++) {
            tiles.push(
                <img
                    key={`${keyPrefix}-${i}-${j}`}
                    src={tileUrl(style.tiles, z, i, j)}
                    alt=""
                    draggable={false}
                    loading="eager"
                    decoding="async"
                    onError={e => {
                        const t = e.currentTarget as HTMLImageElement;
                        if (DEBUG_TILES) { t.style.setProperty('background-color', 'rgba(255,0,0,0.5)'); return; }
                        t.style.opacity = '0';
                        const tries = Number(t.dataset.retry ?? '0');
                        if (tries < 2) {
                            t.dataset.retry = String(tries + 1);
                            const base = t.src.split('?')[0];
                            window.setTimeout(() => { t.src = `${base}?r=${tries + 1}`; }, 900 * (tries + 1));
                        }
                    }}
                    // Reveal with opacity, NOT visibility: a loaded tile set to visibility:visible
                    // overrides the AppDeck hidden-pool's inherited visibility:hidden and paints the
                    // map through the homescreen while maps is backgrounded. Opacity can't escape it.
                    onLoad={e => { (e.currentTarget as HTMLImageElement).style.opacity = '1'; }}
                    className="absolute select-none"
                    style={{
                        left: i * tileWidth, top: j * tileHeight,
                        width: tileWidth + seam, height: tileHeight + seam,   // hairline overlap hides seams
                        filter: style.filter,
                        outline: dbg ? `1px solid ${dbg}` : undefined,
                        outlineOffset: dbg ? '-1px' : undefined,
                    }}
                />,
            );
            if (dbg) {
                tiles.push(
                    <div key={`${keyPrefix}-lbl-${i}-${j}`} className="pointer-events-none absolute select-none"
                        style={{ left: i * tileWidth + 1, top: j * tileHeight + 1, fontSize: Math.max(7, Math.min(11, tileWidth / 6)), lineHeight: 1, color: dbg, textShadow: '0 0 2px #000,0 0 2px #000', fontFamily: 'monospace', fontWeight: 700 }}>
                        {z}/{i}/{j}
                    </div>,
                );
            }
        }
    }
    return tiles;
}

const TileGrid = memo(function TileGrid({ style, width, height, pow, scale, tx, ty, vpW, vpH }: {
    style: MapStyle; width: number; height: number; pow: number; scale: number; tx: number; ty: number; vpW: number; vpH: number;
}) {
    const widthP  = width * pow;
    const heightP = height * pow;
    const scaleP = scale / pow;

    const backdrop = useMemo(
        () => (width && height ? tileLayer(style, BACKDROP_Z, widthP, heightP, scaleP, 0, 0, vpW, vpH, `${style.tiles}bg`, true) : []),
        [style, width, height, widthP, heightP, scaleP, vpW, vpH],
    );

    if (!width || !height) return null;

    const maxZ = styleMaxZoom(style.tiles);
    const need = Math.ceil(Math.log2(Math.max(1, (width * scale) / MAP_WIDTH)));
    const detailZ = Math.max(BACKDROP_Z, Math.min(maxZ, need));

    const detail: ReactNode[] = [];
    for (let z = Math.max(BACKDROP_Z + 1, detailZ - 1); z <= detailZ; z++) {
        detail.push(
            ...tileLayer(style, z, widthP, heightP, scaleP, tx, ty, vpW, vpH, `${style.tiles}${z}`, false),
        );
    }
    return <>{backdrop}{detail}</>;
});

function CtrlBtn({ onClick, label, children }: { onClick: () => void; label: string; children: ReactNode }) {
    return (
        <button
            onClick={onClick}
            aria-label={label}
            className="flex h-9 w-9 items-center justify-center text-ios-blue transition-colors active:bg-black/5 dark:active:bg-white/10"
        >
            {children}
        </button>
    );
}
