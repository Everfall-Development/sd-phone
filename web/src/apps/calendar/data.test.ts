import { describe, expect, it } from 'vitest';
import { applyCalendarChange, parseCalendarChange } from './data';
import type { CalEvent, CalState } from './data';

const EVENT: CalEvent = {
    id: 'calendar-one',
    dayKey: '2026-07-30',
    title: 'City meeting',
    allDay: false,
    start: '09:00',
    end: '10:00',
    location: 'City Hall',
    notes: '',
    color: '#ff453a',
};

const EMPTY: CalState = { events: [], dayNotes: {} };

describe('shared Calendar state', () => {
    it('applies canonical event upserts idempotently', () => {
        const first = applyCalendarChange(EMPTY, {
            operation: 'upsert',
            id: EVENT.id,
            event: EVENT,
        });
        const changed = { ...EVENT, title: 'Updated meeting' };
        const second = applyCalendarChange(first, {
            operation: 'upsert',
            id: changed.id,
            event: changed,
        });
        expect(second.events).toEqual([changed]);
    });

    it('applies day-note clears and owned event deletes', () => {
        const populated: CalState = { events: [EVENT], dayNotes: { '2026-07-30': 'Bring ID' } };
        const cleared = applyCalendarChange(populated, {
            operation: 'note',
            dayKey: '2026-07-30',
            note: '',
        });
        const deleted = applyCalendarChange(cleared, { operation: 'delete', id: EVENT.id });
        expect(deleted).toEqual(EMPTY);
    });

    it('rejects malformed live mutation payloads', () => {
        expect(parseCalendarChange({ operation: 'upsert', event: { id: 'broken' } })).toBeNull();
        expect(parseCalendarChange({ operation: 'delete', id: '' })).toBeNull();
        expect(parseCalendarChange({ operation: 'note', dayKey: '2026-07-30', note: 42 })).toBeNull();
    });
});
