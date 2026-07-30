import { describe, expect, it } from 'vitest';

import { buildForecast, formatHour, normalizeLiveWeather, PROFILES } from './data';

describe('ef_atmos forecast mapping', () => {
    it('uses authoritative event order and the active event remaining time', () => {
        const live = normalizeLiveWeather({
            current: 'CLEAR',
            next: 'RAIN',
            time: { hour: 13, minute: 50 },
            forecast: {
                weatherEvents: [
                    { eventId: 1, weatherType: 'CLEAR', timeRemaining: 60 },
                    { eventId: 2, weatherType: 'RAIN', timeRemaining: 30 },
                    { eventId: 3, weatherType: 'THUNDER', timeRemaining: 45 },
                ],
                currentEventRemainingSeconds: 15 * 60,
                isWeatherPaused: false,
            },
        });

        expect(live).not.toBeNull();
        if (!live) return;

        const forecast = buildForecast(PROFILES[0], live);
        expect(forecast.scheduled).toBe(true);
        expect(forecast.hourly.map(event => event.code)).toEqual(['CLEAR', 'RAIN', 'THUNDER']);
        expect(forecast.hourly.map(event => event.offset)).toEqual([0, 15, 45]);
    });

    it('keeps pause state and formats event starts from synced world time', () => {
        const live = normalizeLiveWeather({
            current: 'OVERCAST',
            next: 'FOGGY',
            forecast: {
                weatherEvents: [
                    { weatherType: 'OVERCAST', timeRemaining: 20 },
                    { weatherType: 'FOGGY', timeRemaining: 25 },
                ],
                currentEventRemainingSeconds: 317,
                isWeatherPaused: true,
            },
        });

        expect(live?.forecast?.paused).toBe(true);
        expect(formatHour(15, { hour: 13, minute: 50 })).toBe('2:05 PM');
    });
});
