import { describe, expect, it } from 'vitest';

import { callEntryTitle, isDialableCallEntry, toCallEntry, type Contact, type RawCall } from './data';

const contacts: Contact[] = [];

describe('phone call display data', () => {
    it('keeps the server-supplied name for business calls', () => {
        const raw: RawCall = {
            id: 'business-call',
            number: 'business:public_relations',
            name: 'Weazel News',
            direction: 'incoming',
            duration: 0,
            calledAt: 1_700_000_000,
        };

        const entry = toCallEntry(raw, contacts);

        expect(entry.name).toBe('Weazel News');
        expect(callEntryTitle(entry)).toBe('Weazel News');
        expect(isDialableCallEntry(entry)).toBe(false);
    });

    it('uses a safe business label when a legacy call has no name', () => {
        const entry = toCallEntry({
            id: 'legacy-business-call',
            number: 'business:police',
            direction: 'incoming',
            duration: 0,
            calledAt: 1_700_000_000,
        }, contacts);

        expect(callEntryTitle(entry)).toBe('Business');
    });
});
