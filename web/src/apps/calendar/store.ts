import { create } from 'zustand';
import { isFiveM } from '@/core/nui';
import {
    deleteCalendarEvent,
    loadCalendar,
    saveCalendarDayNote,
    saveCalendarEvent,
} from './api';
import {
    applyCalendarChange,
    emptyCalendarState,
    loadState,
    parseCalendarChange,
    saveState,
} from './data';
import type { CalEvent, CalState, CalendarChange } from './data';

interface CalendarStore extends CalState {
    hydrated: boolean;
    loading: boolean;
    error: string | null;
    hydrate: () => Promise<boolean>;
    saveEvent: (event: CalEvent) => Promise<boolean>;
    deleteEvent: (id: string) => Promise<boolean>;
    saveDayNote: (dayKey: string, note: string) => Promise<boolean>;
    clearError: () => void;
}

function initialState(): CalState {
    return isFiveM ? emptyCalendarState : loadState();
}

function errorMessage(error: unknown, fallback: string): string {
    return error instanceof Error ? error.message : fallback;
}

function persistBrowser(state: CalState): void {
    if (!isFiveM) saveState(state);
}

export const useCalendarStore = create<CalendarStore>()((set, get) => ({
    ...initialState(),
    hydrated: !isFiveM,
    loading: false,
    error: null,
    async hydrate() {
        if (get().loading) return false;
        set({ loading: true, error: null });
        try {
            const state = await loadCalendar();
            set({ ...state, hydrated: true, loading: false });
            return true;
        } catch (error) {
            set({ loading: false, error: errorMessage(error, 'Calendar could not be loaded.') });
            return false;
        }
    },
    async saveEvent(event) {
        const previous = { events: get().events, dayNotes: get().dayNotes };
        const optimistic = applyCalendarChange(previous, { operation: 'upsert', id: event.id, event });
        set({ ...optimistic, error: null });
        persistBrowser(optimistic);
        if (!isFiveM) return true;

        try {
            const result = await saveCalendarEvent(event);
            if (!result.success || !result.data) {
                set({ ...previous, error: result.message ?? 'Event could not be saved.' });
                return false;
            }
            set(state => ({
                ...applyCalendarChange(state, {
                    operation: 'upsert',
                    id: result.data?.id ?? event.id,
                    event: result.data ?? event,
                }),
                error: null,
            }));
            return true;
        } catch (error) {
            set({ ...previous, error: errorMessage(error, 'Event could not be saved.') });
            return false;
        }
    },
    async deleteEvent(id) {
        const previous = { events: get().events, dayNotes: get().dayNotes };
        const optimistic = applyCalendarChange(previous, { operation: 'delete', id });
        set({ ...optimistic, error: null });
        persistBrowser(optimistic);
        if (!isFiveM) return true;

        try {
            const result = await deleteCalendarEvent(id);
            if (result.success) return true;
            set({ ...previous, error: result.message ?? 'Event could not be deleted.' });
            return false;
        } catch (error) {
            set({ ...previous, error: errorMessage(error, 'Event could not be deleted.') });
            return false;
        }
    },
    async saveDayNote(dayKey, note) {
        const previous = { events: get().events, dayNotes: get().dayNotes };
        const optimistic = applyCalendarChange(previous, { operation: 'note', dayKey, note });
        set({ ...optimistic, error: null });
        persistBrowser(optimistic);
        if (!isFiveM) return true;

        try {
            const result = await saveCalendarDayNote(dayKey, note);
            if (result.success) return true;
            set({ ...previous, error: result.message ?? 'Day note could not be saved.' });
            return false;
        } catch (error) {
            set({ ...previous, error: errorMessage(error, 'Day note could not be saved.') });
            return false;
        }
    },
    clearError() {
        set({ error: null });
    },
}));

export function ingestCalendarChange(change: CalendarChange): void {
    useCalendarStore.setState(state => ({ ...applyCalendarChange(state, change), error: null }));
}

function handleCalendarMessage(event: MessageEvent<unknown>): void {
    if (event.source !== window && event.source !== window.parent) return;
    if (typeof event.data !== 'object' || event.data === null) return;
    const action = Reflect.get(event.data, 'action');
    if (action === 'sd-phone:profileReset') {
        useCalendarStore.setState({ ...emptyCalendarState, hydrated: false, error: null });
        void useCalendarStore.getState().hydrate();
        return;
    }
    if (action !== 'sd-phone:calendar:changed') return;
    const change = parseCalendarChange(Reflect.get(event.data, 'data'));
    if (change) ingestCalendarChange(change);
}

if (typeof window !== 'undefined') window.addEventListener('message', handleCalendarMessage);
