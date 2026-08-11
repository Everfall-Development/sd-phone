import { useCallback, useEffect } from 'react';

import { useNuiEvent } from '@/hooks/useNuiEvent';
import { useTheme } from '@/stores/themeStore';
import { resolveTone } from '@/apps/settings/tones';
import { startRingtone } from '@/apps/settings/tonePlayer';
import { startRing } from './calls/ringtone';
import { getCurrentCall } from './callsApi';
import { useCallStore } from '@/stores/callStore';

/**
 * Call state, owned ABOVE the phone shell.
 *
 * CallLayer only exists while the phone is open, and useNuiEvent drops any message whose handler
 * isn't mounted - so a ring that arrived while the phone was closed, or while the auto-open was
 * refused (dead, swimming, another NUI holding focus), reached nothing at all: no store, no island,
 * no ringtone. The player found the call only by opening the phone themselves and landing on the
 * hydrate. This component never unmounts, so the ring is heard and the island lights the moment the
 * call starts, and opening the phone is a reveal rather than the delivery mechanism.
 *
 * Presentation stays in CallLayer; this owns the store, the resync and the ringtone.
 */
export function CallSession() {
    const phase   = useCallStore(s => s.phase);
    const channel = useCallStore(s => s.channel);
    const { ringtone, ringtoneVol, customRingtones } = useTheme('ringtone', 'ringtoneVol', 'customRingtones');

    useNuiEvent('sd-phone:call:incoming',  useCallback((data) => useCallStore.getState().incoming(data), []));
    useNuiEvent('sd-phone:call:outgoing',  useCallback((data) => useCallStore.getState().outgoing(data), []));
    useNuiEvent('sd-phone:call:connected', useCallback((data) => useCallStore.getState().connected(data), []));
    useNuiEvent('sd-phone:call:ended',     useCallback(() => useCallStore.getState().ended(), []));
    useNuiEvent('sd-phone:call:roster',    useCallback((data) => useCallStore.getState().roster(data ?? {}), []));

    // Resync on boot and on every open: a call outlives a NUI reload and a resource restart, both of
    // which leave the session live server-side. A null answer is deliberately left alone rather than
    // clearing the store, so an in-flight read can't wipe a dial whose push already landed.
    const resync = useCallback(() => {
        void getCurrentCall().then(cur => { if (cur) useCallStore.getState().hydrate(cur); });
    }, []);

    useEffect(resync, [resync]);
    useNuiEvent('sd-phone:open', resync);

    // Rings wherever the phone is - in hand, or in a pocket behind the island. Volume is read but
    // not depended on, so dragging the slider mid-ring doesn't restart the tone from the top.
    useEffect(() => {
        if (!phase || phase === 'active') return;
        if (phase === 'incoming') {
            return startRingtone(resolveTone('ringtone', ringtone, customRingtones).url, ringtoneVol / 100);
        }
        return startRing('ringback');
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [channel, phase, ringtone, customRingtones]);

    return null;
}
