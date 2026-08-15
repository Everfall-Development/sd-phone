import { useState, useSyncExternalStore } from 'react';

import { t } from '@/i18n';
import { apiData } from '@/core/api';
import { useAsyncData } from '@/hooks/useAsyncData';
import { AlertDialog } from '@/ui/AlertDialog';
import { requestPhoneReset, usePhoneReset, type PhoneResetScope } from '@/core/phoneReset';
import { ListGroup, ListRow } from '@/ui/ListGroup';
import { SubPage } from '../SettingsSubPage';

type Deadlines = Record<PhoneResetScope, number>;

const NONE: Deadlines = { settings: 0, erase: 0 };

let nowSnapshot = Date.now();
let nowTimer: number | undefined;
const nowListeners = new Set<() => void>();

function getNowSnapshot(): number {
    return nowSnapshot;
}

function tickNow(): void {
    nowSnapshot = Date.now();
    for (const listener of nowListeners) listener();
}

function subscribeNow(listener: () => void): () => void {
    nowListeners.add(listener);
    if (nowListeners.size === 1) {
        nowSnapshot = Date.now();
        nowTimer = window.setInterval(tickNow, 250);
    }

    return function unsubscribeNow() {
        nowListeners.delete(listener);
        if (nowListeners.size > 0 || nowTimer === undefined) return;
        window.clearInterval(nowTimer);
        nowTimer = undefined;
    };
}

async function fetchResetDeadlines(): Promise<Deadlines | null> {
    const data = await apiData<{ settings?: number; erase?: number }>('sd-phone:settings:resetCooldown');
    if (!data) return null;
    const now = Date.now();
    return {
        settings: data.settings ? now + data.settings : 0,
        erase: data.erase ? now + data.erase : 0,
    };
}

export function ResetPhonePage({ onBack }: { onBack: () => void }) {
    const [confirm, setConfirm] = useState<PhoneResetScope | null>(null);
    const [localDeadlines, setLocalDeadlines] = useState<Deadlines>(NONE);
    const resetPending = usePhoneReset(state => state.pending);
    const resetError = usePhoneReset(state => state.error);
    const now = useSyncExternalStore(subscribeNow, getNowSnapshot, getNowSnapshot);
    const { data: serverDeadlines, loading, settled } = useAsyncData(fetchResetDeadlines, []);
    const deadlines: Deadlines = {
        settings: Math.max(serverDeadlines?.settings ?? 0, localDeadlines.settings),
        erase: Math.max(serverDeadlines?.erase ?? 0, localDeadlines.erase),
    };
    const unavailable = settled && serverDeadlines === null;

    function leftFor(scope: PhoneResetScope): number {
        return Math.max(0, Math.ceil((deadlines[scope] - now) / 1000));
    }

    function run(scope: PhoneResetScope, windowMs: number) {
        if (resetPending) return;
        setConfirm(null);
        setLocalDeadlines(deadlines => ({ ...deadlines, [scope]: Date.now() + windowMs }));
        requestPhoneReset(scope);
    }

    function subFor(scope: PhoneResetScope): string | undefined {
        if (unavailable) return t('settings.resetUnavailable', 'Unavailable');
        const secs = leftFor(scope);
        return secs > 0 ? t('settings.resetAvailableIn', 'Available again in {n}s', { n: secs }) : undefined;
    }

    return (
        <>
            <SubPage title={t('settings.resetPhone', 'Reset Phone')} onBack={onBack}>
                <ListGroup footer={t('settings.resetAllFooter', 'Resetting puts every setting back to default. It does not sign you out or remove anything you have installed.')}>
                    <ListRow
                        label={t('settings.resetAllSettings', 'Reset All Settings')}
                        sub={subFor('settings')}
                        destructive
                        disabled={loading || unavailable || resetPending || leftFor('settings') > 0}
                        onPress={() => setConfirm('settings')}
                    />
                </ListGroup>

                <ListGroup footer={t('settings.eraseAllFooter', 'Erases everything on this phone and takes you back through setup. Your saved passwords stay in the Passwords app, so you can sign back into your accounts. This cannot be undone.')}>
                    <ListRow
                        label={t('settings.eraseAllContent', 'Reset Phone Fully')}
                        sub={subFor('erase')}
                        destructive
                        disabled={loading || unavailable || resetPending || leftFor('erase') > 0}
                        onPress={() => setConfirm('erase')}
                    />
                </ListGroup>

                {resetError && (
                    <p role="alert" className="px-7 text-[14px] font-medium text-ios-red">
                        {resetError}
                    </p>
                )}
            </SubPage>

            {confirm === 'settings' && (
                <AlertDialog
                    title={t('settings.resetAllTitle', 'Reset All Settings?')}
                    message={t('settings.resetAllMessage', 'Your theme, wallpaper, Home Screen layout and other preferences go back to default. Your apps, accounts, passcode and contact card are kept.')}
                    confirmLabel={t('settings.resetConfirm', 'Reset')}
                    destructive
                    onCancel={() => setConfirm(null)}
                    onConfirm={() => run('settings', 2000)}
                />
            )}

            {confirm === 'erase' && (
                <AlertDialog
                    title={t('settings.eraseAllTitle', 'Reset Phone Fully?')}
                    message={t('settings.eraseAllMessage', 'Your phone is wiped back to factory defaults and you will be taken through setup again. Your saved passwords stay in the Passwords app, so you can sign back into your accounts. Server-side data such as mail accounts and group memberships is preserved.')}
                    confirmLabel={t('settings.eraseConfirm', 'Reset')}
                    destructive
                    onCancel={() => setConfirm(null)}
                    onConfirm={() => run('erase', 30000)}
                />
            )}
        </>
    );
}
