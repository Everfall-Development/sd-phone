import { create } from 'zustand';

// Factory-reset mailbox: Settings requests a reset, App.tsx performs it in place
// (clears storage, resets stores, remounts the tree into the setup flow).

export type PhoneResetScope = 'erase' | 'settings';

interface PhoneResetState {
    nonce: number;
    scope: PhoneResetScope;
    pending: boolean;
    error: string | null;
    request: (scope: PhoneResetScope) => void;
    fail: (message: string) => void;
    complete: () => void;
}

export const usePhoneReset = create<PhoneResetState>(set => ({
    nonce: 0,
    scope: 'settings',
    pending: false,
    error: null,
    request: scope => set(state => {
        if (state.pending) return state;
        return { nonce: state.nonce + 1, scope, pending: true, error: null };
    }),
    fail: message => set({ pending: false, error: message }),
    complete: () => set({ pending: false, error: null }),
}));

export function requestPhoneReset(scope: PhoneResetScope): void {
    usePhoneReset.getState().request(scope);
}

export function failPhoneReset(message: string): void {
    usePhoneReset.getState().fail(message);
}

export function completePhoneReset(): void {
    usePhoneReset.getState().complete();
}
