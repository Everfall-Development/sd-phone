import { fetchNui } from '@/core/nui';
import { MAX_TILE_ZOOM, MIN_TILE_ZOOM, TILE_SOURCES, mapTileGrid, tileUrl } from './data';
import type { MapTileStyle } from './data';

const BASE_LAYER_Z = MIN_TILE_ZOOM;

function testTile(url: string): Promise<boolean> {
    return new Promise(resolve => {
        const img = new Image();
        let done = false;
        const finish = (ok: boolean) => { if (!done) { done = true; resolve(ok); } };
        img.onload  = () => finish(img.naturalWidth > 0);
        img.onerror = () => finish(false);
        img.src = url;
        setTimeout(() => finish(false), 6000);
    });
}

interface StyleReport {
    name: MapTileStyle;
    base: string;
    maxZoom: number;
    deepestOk: number;
    levels: { z: number; ok: boolean }[];
}

async function checkStyle(name: MapTileStyle): Promise<StyleReport> {
    const src = TILE_SOURCES[name];
    const top = Math.min(MAX_TILE_ZOOM + 2, src.maxZoom + 2);
    const levels: { z: number; ok: boolean }[] = [];
    for (let z = BASE_LAYER_Z; z <= top; z++) {
        const grid = mapTileGrid(z);
        const x = Math.floor(grid.columns / 2);
        const y = Math.floor(grid.rows / 2);
        levels.push({ z, ok: await testTile(tileUrl(name, z, x, y)) });
    }
    let deepestOk = -1;
    for (const l of levels) if (l.ok) deepestOk = l.z;
    return { name, base: src.base, maxZoom: src.maxZoom, deepestOk, levels };
}

let running = false;

export function initTileCheck(): void {
    window.addEventListener('message', async (event: MessageEvent) => {
        const msg = event.data as { action?: string } | undefined;
        if (!msg || msg.action !== 'sd-phone:maps:tilecheck' || running) return;
        running = true;
        try {
            const styles: StyleReport[] = [await checkStyle('everfall')];
            await fetchNui('sd-phone:maps:tilecheckResult', { styles });
        } finally {
            running = false;
        }
    });
}
