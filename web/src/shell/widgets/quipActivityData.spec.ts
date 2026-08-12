import { describe, expect, it } from 'vitest';

import { SEED_NOTIFICATIONS } from '@/apps/birdy/data';
import { projectQuipActivity } from './quipActivityData';

describe('Quip activity projection', () => {
    it('keeps reply actors and post previews for compact rows', () => {
        const entry = projectQuipActivity(SEED_NOTIFICATIONS[0]);

        expect(entry.kind).toBe('reply');
        expect(entry.actor).toBe('Kilo Tire & Wheel');
        expect(entry.preview).toContain('we are ten minutes');
    });

    it('keeps follow activity compact without inventing a preview', () => {
        const entry = projectQuipActivity(SEED_NOTIFICATIONS[3]);

        expect(entry.kind).toBe('follow');
        expect(entry.actor).toBe('Kilo Tire & Wheel');
        expect(entry.preview).toBeUndefined();
    });
});
