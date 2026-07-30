import { create } from 'zustand';

import { fetchNui } from '@/core/nui';
import type { WeatherPayload } from '@/core/types';
import { normalizeLiveWeather } from './data';
import type { LiveWeather } from './data';

interface WeatherStore {
    live: LiveWeather | null;
}

export const useWeatherStore = create<WeatherStore>(() => ({ live: null }));

export function ingestWeather(payload: WeatherPayload | undefined): void {
    const live = normalizeLiveWeather(payload);
    if (live) useWeatherStore.setState({ live });
}

let requested = false;

export async function requestWeatherSnapshot(): Promise<void> {
    if (requested) return;
    requested = true;

    try {
        const payload = await fetchNui<WeatherPayload>('sd-phone:weather:get');
        ingestWeather(payload);
    } catch {
        requested = false;
    }
}
