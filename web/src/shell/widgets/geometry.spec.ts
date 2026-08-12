import { describe, expect, it } from 'vitest';

import { placeNewApps, seedHomeSlots } from './geometry';

function appIds(count: number): string[] {
    return Array.from({ length: count }, (_, index) => `app-${index + 1}`);
}

describe('home screen app placement', () => {
    it('fills the first screen before creating another populated screen', () => {
        const ids = appIds(25);
        const slots = seedHomeSlots(ids, 24);

        expect(slots.slice(0, 24)).toEqual(ids.slice(0, 24));
        expect(slots[24]).toBe('app-25');
        expect(slots).toHaveLength(72);
    });

    it('places an added app in an open first-screen cell before later screens', () => {
        const slots = seedHomeSlots(appIds(12), 24);
        slots[24] = 'later-screen';

        const placed = placeNewApps(slots, ['new-app'], [], 24);

        expect(placed[12]).toBe('new-app');
        expect(placed[24]).toBe('later-screen');
    });

    it('uses an unavailable first-screen placeholder before moving a visible app', () => {
        const ids = appIds(24);
        const slots = seedHomeSlots(ids, 24);
        slots[5] = 'disabled-app';
        const visible = new Set(ids.filter(id => id !== 'app-6'));

        const placed = placeNewApps(slots, ['new-app'], [], 24, visible);

        expect(placed[5]).toBe('new-app');
        expect(placed[24]).toBe('disabled-app');
    });

    it('makes room on a full first screen for each newly added app', () => {
        const ids = appIds(24);
        const slots = seedHomeSlots(ids, 24);

        const placed = placeNewApps(slots, ['new-one', 'new-two'], [], 24, new Set(ids));

        expect(placed[22]).toBe('new-two');
        expect(placed[23]).toBe('new-one');
        expect(placed.slice(24)).toContain('app-23');
        expect(placed.slice(24)).toContain('app-24');
    });
});
