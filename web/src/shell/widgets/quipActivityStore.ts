import { create } from 'zustand';

import { isFiveM } from '@/core/nui';
import type { BirdyNotification } from '@/apps/birdy/data';

interface QuipActivityState {
    unread:    number;
    activity:  BirdyNotification[];
    refresh:   () => void;
}

let refreshInFlight = false;

function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === 'object' && value !== null;
}

function actionOf(value: unknown): string | undefined {
    if (!isRecord(value)) return undefined;
    return typeof value.action === 'string' ? value.action : undefined;
}

function launchedAppId(value: unknown): string | undefined {
    if (!isRecord(value) || !isRecord(value.data)) return undefined;
    return typeof value.data.id === 'string' ? value.data.id : undefined;
}

export const useQuipActivity = create<QuipActivityState>((set) => ({
    unread:   0,
    activity: [],
    refresh:  () => {
        if (refreshInFlight) return;
        refreshInFlight = true;
        void import('@/apps/birdy/birdyApi')
            .then(({ apiNotificationCount, apiNotificationPreview }) => Promise.all([
                apiNotificationCount(),
                apiNotificationPreview(),
            ]))
            .then(([unread, activity]) => set({
                unread:   Math.max(0, Math.floor(unread)),
                activity: activity.slice(0, 8),
            }))
            .catch(() => {})
            .finally(() => { refreshInFlight = false; });
    },
}));

function ensureNuiInvalidation(): void {
    if (typeof window === 'undefined') return;
    window.addEventListener('message', (event: MessageEvent) => {
        const action = actionOf(event.data);
        if (action === 'sd-phone:open' || action === 'sd-phone:birdy:notification'
            || (action === 'sd-phone:launchApp' && launchedAppId(event.data) === 'birdy')) {
            useQuipActivity.getState().refresh();
        }
    });
}

ensureNuiInvalidation();
if (!isFiveM) useQuipActivity.getState().refresh();
