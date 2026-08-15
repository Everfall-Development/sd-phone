import { describe, expect, it } from 'vitest';

import {
    completePhoneReset,
    failPhoneReset,
    requestPhoneReset,
    usePhoneReset,
} from './phoneReset';

describe('phone reset mailbox', () => {
    it('prevents duplicate resets and allows a retry after failure', () => {
        const initialNonce = usePhoneReset.getState().nonce;

        requestPhoneReset('settings');
        const pending = usePhoneReset.getState();
        expect(pending.nonce).toBe(initialNonce + 1);
        expect(pending.scope).toBe('settings');
        expect(pending.pending).toBe(true);
        expect(pending.error).toBeNull();

        requestPhoneReset('erase');
        expect(usePhoneReset.getState().nonce).toBe(pending.nonce);
        expect(usePhoneReset.getState().scope).toBe('settings');

        failPhoneReset('Database unavailable');
        expect(usePhoneReset.getState().pending).toBe(false);
        expect(usePhoneReset.getState().error).toBe('Database unavailable');

        requestPhoneReset('erase');
        expect(usePhoneReset.getState().scope).toBe('erase');
        expect(usePhoneReset.getState().pending).toBe(true);
        expect(usePhoneReset.getState().error).toBeNull();

        completePhoneReset();
        expect(usePhoneReset.getState().pending).toBe(false);
        expect(usePhoneReset.getState().error).toBeNull();
    });
});
