import { describe, expect, it } from 'vitest';

import { deliverReadyDeepLinks } from './customAppDeepLinks';

describe('custom app early deep-link delivery', () => {
    it('releases deep links without releasing SDK-dependent messages', () => {
        const delivered: unknown[] = [];
        const invalidation = { type: 'invalidate' };
        const deepLink = { action: 'deepLink', data: { route: 'invoices' } };

        const remaining = deliverReadyDeepLinks([invalidation, deepLink], (message) => {
            delivered.push(message);
        });

        expect(delivered).toEqual([deepLink]);
        expect(remaining).toEqual([invalidation]);
    });
});
