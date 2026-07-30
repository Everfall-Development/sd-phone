import { readJson, writeJson } from '@/lib/storage';
import { format12h } from '@/lib/time';

const STORAGE_KEY = 'sd-phone:calendar:v1';

export interface CalEvent {
    id:       string;
    dayKey:   string;
    title:    string;
    allDay:   boolean;
    start?:   string;
    end?:     string;
    location: string;
    notes:    string;
    color:    string;
}

export interface CalState {
    events:   CalEvent[];
    dayNotes: Record<string, string>;
}

export type CalendarChange =
    | { operation: 'upsert'; id: string; event: CalEvent }
    | { operation: 'delete'; id: string }
    | { operation: 'note'; dayKey: string; note: string };

export const emptyCalendarState: CalState = { events: [], dayNotes: {} };

export function loadState(): CalState {
    const raw = readJson<Partial<CalState>>(STORAGE_KEY);
    return raw
        ? {
            events:   Array.isArray(raw.events) ? raw.events : [],
            dayNotes: raw.dayNotes && typeof raw.dayNotes === 'object' ? raw.dayNotes : {},
        }
        : emptyCalendarState;
}

export function saveState(s: CalState): void {
    writeJson(STORAGE_KEY, s);
}

export function applyCalendarChange(state: CalState, change: CalendarChange): CalState {
    if (change.operation === 'delete') {
        return { ...state, events: state.events.filter(event => event.id !== change.id) };
    }
    if (change.operation === 'note') {
        const dayNotes = { ...state.dayNotes };
        if (change.note) dayNotes[change.dayKey] = change.note;
        else delete dayNotes[change.dayKey];
        return { ...state, dayNotes };
    }

    const event = change.event;
    return {
        ...state,
        events: state.events.some(item => item.id === event.id)
            ? state.events.map(item => item.id === event.id ? event : item)
            : [...state.events, event],
    };
}

function textField(value: unknown, key: string): string | null {
    if (typeof value !== 'object' || value === null) return null;
    const field = Reflect.get(value, key);
    return typeof field === 'string' ? field : null;
}

export function parseCalendarEvent(value: unknown): CalEvent | null {
    if (typeof value !== 'object' || value === null) return null;
    const id = textField(value, 'id');
    const eventDayKey = textField(value, 'dayKey');
    const title = textField(value, 'title');
    const location = textField(value, 'location');
    const notes = textField(value, 'notes');
    const color = textField(value, 'color');
    const allDay = Reflect.get(value, 'allDay');
    const start = Reflect.get(value, 'start');
    const end = Reflect.get(value, 'end');
    if (!id || !eventDayKey || !title || location === null || notes === null || !color) return null;
    if (typeof allDay !== 'boolean') return null;
    if (start !== undefined && start !== null && typeof start !== 'string') return null;
    if (end !== undefined && end !== null && typeof end !== 'string') return null;
    return {
        id,
        dayKey: eventDayKey,
        title,
        allDay,
        start: typeof start === 'string' ? start : undefined,
        end: typeof end === 'string' ? end : undefined,
        location,
        notes,
        color,
    };
}

export function parseCalendarChange(value: unknown): CalendarChange | null {
    if (typeof value !== 'object' || value === null) return null;
    const operation = Reflect.get(value, 'operation');
    if (operation === 'upsert') {
        const event = parseCalendarEvent(Reflect.get(value, 'event'));
        return event ? { operation, id: event.id, event } : null;
    }
    if (operation === 'delete') {
        const id = textField(value, 'id');
        return id ? { operation, id } : null;
    }
    if (operation === 'note') {
        const eventDayKey = textField(value, 'dayKey');
        const note = textField(value, 'note');
        return eventDayKey && note !== null ? { operation, dayKey: eventDayKey, note } : null;
    }
    return null;
}


export function dayKey(d: Date): string {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
}

export function isSameDay(a: Date, b: Date): boolean {
    return a.getFullYear() === b.getFullYear()
        && a.getMonth()    === b.getMonth()
        && a.getDate()     === b.getDate();
}

export function addMonths(d: Date, n: number): Date {
    return new Date(d.getFullYear(), d.getMonth() + n, 1);
}

export const MONTH_NAMES = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
];

export const WEEKDAY_SHORT = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

export function monthGrid(d: Date): Date[] {
    const first = new Date(d.getFullYear(), d.getMonth(), 1);
    const startCol = first.getDay();
    const gridStart = new Date(d.getFullYear(), d.getMonth(), 1 - startCol);
    const out: Date[] = [];
    for (let i = 0; i < 42; i++) {
        out.push(new Date(gridStart.getFullYear(), gridStart.getMonth(), gridStart.getDate() + i));
    }
    return out;
}

export function formatLongDate(d: Date): string {
    const wk = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'][d.getDay()];
    return `${wk}, ${MONTH_NAMES[d.getMonth()]} ${d.getDate()}`;
}

export function formatTime(hhmm: string): string {
    const [hStr, mStr] = hhmm.split(':');
    const h = Number(hStr);
    const m = Number(mStr);
    return format12h(h, m);
}

export { newId } from '@/lib/format';

export const EVENT_COLORS = [
    '#ff453a', // red
    '#ff9f0a', // orange
    '#ffd60a', // yellow
    '#34c759', // green
    '#0a84ff', // blue
    '#5e5ce6', // indigo
    '#bf5af2', // purple
];
