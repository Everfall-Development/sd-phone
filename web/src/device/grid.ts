import { useSyncExternalStore } from 'react';

import { device } from '@device';
import type { Density, DeviceDensity, DeviceGrid, DeviceScreen } from './types';

export const DENSITIES: readonly Density[] = ['compact', 'default', 'large'];

export const DOCK_BOTTOM = 20;
export const DOCK_PAD_Y  = 28;
export const DOTS_GAP    = 6;

export function isDensity(v: unknown): v is Density {
    return typeof v === 'string' && (DENSITIES as readonly string[]).includes(v);
}

export const DOTS_RESERVE = 34;
const LABEL_H = 28;
const DOTS_CLEARANCE = 58;
const MIN_ROW_GAP = 20;

export function stripReserve(g: DeviceGrid, dockHidden = false): number {
    return dockHidden ? DOTS_RESERVE : g.icon + 26;
}

export function deriveGrid(screen: Pick<DeviceScreen, 'w'>, base: DeviceGrid, p: DeviceDensity): DeviceGrid {
    return {
        cols:      p.cols,
        rows:      p.rows,
        padX:      p.padX,
        icon:      p.icon,
        colStride: (screen.w - 2 * p.padX - p.icon) / (p.cols - 1),
        rowY0:     base.rowY0,
        rowStride: p.icon + (base.rowStride - base.icon),
        stripTop:  base.stripTop,
    };
}

const cache = new Map<Density, DeviceGrid>();

export function gridFor(d: Density): DeviceGrid {
    const hit = cache.get(d);
    if (hit) return hit;

    const base = device.screen.grid;
    const out = d === 'default' ? base : deriveGrid(device.screen, base, device.screen.densities[d]);
    cache.set(d, out);
    return out;
}

const plusCache = new Map<Density, DeviceGrid>();

export function gridForDock(d: Density, dockHidden: boolean): DeviceGrid {
    if (!dockHidden) return gridFor(d);
    const hit = plusCache.get(d);
    if (hit) return hit;

    const base = gridFor(d);
    const rows = base.rows + 1;
    const available = device.screen.h - base.stripTop - DOTS_CLEARANCE;
    const stride = Math.floor((available - base.rowY0 - base.icon - LABEL_H) / (rows - 1));
    const out = stride >= base.icon + MIN_ROW_GAP
        ? { ...base, rows, rowStride: Math.min(base.rowStride, stride) }
        : base;
    plusCache.set(d, out);
    return out;
}

let active: Density = 'default';
let extraRow = false;
const listeners = new Set<() => void>();

export function getGrid(): DeviceGrid {
    return gridForDock(active, extraRow);
}

export function setExtraRow(v: boolean): void {
    if (v === extraRow) return;
    extraRow = v;
    for (const fn of listeners) fn();
}

export function getDensity(): Density {
    return active;
}

export function setDensity(d: Density): void {
    if (d === active) return;
    active = d;
    for (const fn of listeners) fn();
}

function subscribe(fn: () => void): () => void {
    listeners.add(fn);
    return () => { listeners.delete(fn); };
}

export function useGrid(): DeviceGrid {
    return useSyncExternalStore(subscribe, getGrid, getGrid);
}
