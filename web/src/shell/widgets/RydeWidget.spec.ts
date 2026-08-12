import { describe, expect, it } from 'vitest';

import type { RydeSync } from '@/apps/ryde/rydeApi';
import { activeRydeWidgetRide, rydeStatusLabel } from './RydeWidget';

const rider = {
    id: 'ride-1',
    status: 'in_progress',
    pickup: { label: 'Legion Square', x: 195, y: -930 },
    dropoff: { label: 'LSIA', x: -1037, y: -2738 },
    distance: 4.2,
};

describe('Ryde widget projections', () => {
    it('prefers the rider trip when both roles are present', () => {
        const sync: RydeSync = { rider, driver: { ...rider, id: 'driver-ride' } };
        expect(activeRydeWidgetRide(sync)).toEqual({ role: 'rider', ride: rider });
    });

    it('returns the driver trip when there is no rider trip', () => {
        const sync: RydeSync = { driver: rider };
        expect(activeRydeWidgetRide(sync)).toEqual({ role: 'driver', ride: rider });
    });

    it('uses role-specific pickup status language', () => {
        expect(rydeStatusLabel('enroute_pickup', 'rider')).toBe('Driver on the way');
        expect(rydeStatusLabel('enroute_pickup', 'driver')).toBe('Heading to pickup');
    });

    it('drops terminal rides', () => {
        expect(activeRydeWidgetRide({ rider: { ...rider, status: 'completed' } })).toBeNull();
        expect(activeRydeWidgetRide({ driver: { ...rider, status: 'cancelled' } })).toBeNull();
    });

    it('keeps an active driver trip after authorization loss', () => {
        const sync: RydeSync = { driver: rider, driverAllowed: false, duty: false };
        expect(activeRydeWidgetRide(sync)).toEqual({ role: 'driver', ride: rider });
    });
});
