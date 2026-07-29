import { describe, expect, it } from 'vitest';
import { applyNoteChange, type Note, type NotesState } from './data';

function note(id: string, body: string): Note {
    return {
        id,
        body,
        sketches: [],
        images: [],
        createdAt: '2026-07-29T00:00:00.000Z',
        updatedAt: '2026-07-29T00:00:00.000Z',
    };
}

describe('applyNoteChange', () => {
    it('adds a note received from another connected device', () => {
        const state: NotesState = { notes: [note('one', 'First')] };
        const incoming = note('two', 'Second');

        expect(applyNoteChange(state, { operation: 'upsert', note: incoming, id: incoming.id }))
            .toEqual({ notes: [incoming, state.notes[0]] });
    });

    it('replaces an existing note without duplicating it', () => {
        const state: NotesState = { notes: [note('one', 'Before')] };
        const incoming = note('one', 'After');

        expect(applyNoteChange(state, { operation: 'upsert', note: incoming, id: incoming.id }))
            .toEqual({ notes: [incoming] });
    });

    it('removes a deleted note', () => {
        const state: NotesState = { notes: [note('one', 'First'), note('two', 'Second')] };

        expect(applyNoteChange(state, { operation: 'delete', id: 'one' }))
            .toEqual({ notes: [state.notes[1]] });
    });
});
