import { apiCall, apiData, type Envelope } from '@/core/api';
import { isFiveM } from '@/core/nui';
import { loadState } from './data';
import type { CalEvent, CalState } from './data';

export async function loadCalendar(): Promise<CalState> {
    if (!isFiveM) return loadState();
    const state = await apiData<CalState>('sd-phone:calendar:list');
    if (!state) throw new Error('Calendar could not be loaded.');
    return state;
}

export async function saveCalendarEvent(event: CalEvent): Promise<Envelope<CalEvent>> {
    if (!isFiveM) return { success: true, data: event };
    return apiCall<CalEvent>('sd-phone:calendar:save', event);
}

export async function deleteCalendarEvent(id: string): Promise<Envelope<{ id: string }>> {
    if (!isFiveM) return { success: true, data: { id } };
    return apiCall<{ id: string }>('sd-phone:calendar:delete', { id });
}

export async function saveCalendarDayNote(
    dayKey: string,
    note: string,
): Promise<Envelope<{ dayKey: string; note: string }>> {
    if (!isFiveM) return { success: true, data: { dayKey, note } };
    return apiCall<{ dayKey: string; note: string }>('sd-phone:calendar:note', { dayKey, note });
}
