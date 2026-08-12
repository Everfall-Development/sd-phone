import { describe, expect, it } from 'vitest';

import {
    MAP_CENTER,
    MAX_TILE_ZOOM,
    MIN_TILE_ZOOM,
    gameToMap,
    mapTileGrid,
    mapToGame,
    pctToWorld,
    projectPct,
    tileUrl,
} from './data';

describe('Everfall map projection', () => {
    it('keeps the established origin and inverts GTA coordinates', () => {
        expect(gameToMap(0, 0)).toEqual(MAP_CENTER);

        const landmarks = [
            { x: 195, y: -930 },
            { x: -1037, y: -2738 },
            { x: -581.12, y: -1072.53 },
            { x: 895.7, y: -179.3 },
            { x: 425.1, y: -979.5 },
        ];
        for (const location of landmarks) {
            const mapped = gameToMap(location.x, location.y);
            expect(mapToGame(mapped[0], mapped[1]).x).toBeCloseTo(location.x, 8);
            expect(mapToGame(mapped[0], mapped[1]).y).toBeCloseTo(location.y, 8);
        }
    });

    it('round-trips visible map percentages', () => {
        const location = { x: -1037, y: -2738 };
        const pct = projectPct(location.x, location.y);
        const roundTrip = pctToWorld(pct.left, pct.top);

        expect(roundTrip.x).toBeCloseTo(location.x, 8);
        expect(roundTrip.y).toBeCloseTo(location.y, 8);
    });

    it('uses the rectangular shared tile pyramid', () => {
        expect(mapTileGrid(MIN_TILE_ZOOM)).toEqual({ columns: 2, rows: 3 });
        expect(mapTileGrid(MAX_TILE_ZOOM)).toEqual({ columns: 64, rows: 96 });
        expect(tileUrl('everfall', MAX_TILE_ZOOM, 12, 34)).toBe(
            'https://files.coolgingerginger.me/tiles/7/12/34.png',
        );
    });
});
