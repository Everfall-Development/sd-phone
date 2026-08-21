import { create } from 'zustand';

// Cross-app deep links ("open Maps at this waypoint", "message this number").
// Zustand-backed mailbox: requestOpenX stores a take-once target and bumps a
// nonce; App.tsx subscribes via onOpenX to switch apps, and the target app
// consumes the payload with takeXTarget on mount. The exported function API
// is kept stable so the many requestOpenX call sites never change.

export interface MapsTarget {
    label: string;
    x: number;
    y: number;
    icon?: string;
    color?: string;
    companyId?: string;
}

export interface MessagesTarget {
    number: string;
    name?: string;
}

export interface MailTarget {
    to?: string;
    message?: { folder: string; msgId: string; accountId?: string };
}

export interface BusinessesThreadTarget {
    route?: 'inbox';
    entityType?: 'thread';
    entityId?: string;
    scope: 'personal' | 'job';
    thread: string;
}

export interface BusinessesCompanyTarget {
    route: 'directory';
    entityType: 'business';
    entityId: string;
}

export type BusinessesTarget = BusinessesThreadTarget | BusinessesCompanyTarget;

interface DeeplinkState {
    mapsNonce: number;
    mapsTarget: MapsTarget | null;
    messagesNonce: number;
    messagesTarget: MessagesTarget | null;
    mailNonce: number;
    mailTarget: MailTarget | null;
    businessesNonce: number;
    businessesTarget: BusinessesTarget | null;
}

const useDeeplinkStore = create<DeeplinkState>(() => ({
    mapsNonce: 0,
    mapsTarget: null,
    messagesNonce: 0,
    messagesTarget: null,
    mailNonce: 0,
    mailTarget: null,
    businessesNonce: 0,
    businessesTarget: null,
}));

export function requestOpenMaps(target?: MapsTarget | null): void {
    useDeeplinkStore.setState((s) => ({ mapsTarget: target ?? null, mapsNonce: s.mapsNonce + 1 }));
}

export function takeMapsTarget(): MapsTarget | null {
    const t = useDeeplinkStore.getState().mapsTarget;
    useDeeplinkStore.setState({ mapsTarget: null });
    return t;
}

export function onOpenMaps(handler: () => void): () => void {
    return useDeeplinkStore.subscribe((s, prev) => {
        if (s.mapsNonce !== prev.mapsNonce) handler();
    });
}

export function requestOpenMessages(target: MessagesTarget): void {
    useDeeplinkStore.setState((s) => ({
        messagesTarget: target,
        messagesNonce: s.messagesNonce + 1,
    }));
}

export function peekMessagesTarget(): MessagesTarget | null {
    return useDeeplinkStore.getState().messagesTarget;
}

export function clearMessagesTarget(): void {
    useDeeplinkStore.setState({ messagesTarget: null });
}

export function onOpenMessages(handler: () => void): () => void {
    return useDeeplinkStore.subscribe((s, prev) => {
        if (s.messagesNonce !== prev.messagesNonce) handler();
    });
}

export function requestOpenMail(target: MailTarget): void {
    useDeeplinkStore.setState((s) => ({ mailTarget: target, mailNonce: s.mailNonce + 1 }));
}

export function takeMailTarget(): MailTarget | null {
    const t = useDeeplinkStore.getState().mailTarget;
    useDeeplinkStore.setState({ mailTarget: null });
    return t;
}

export function onOpenMail(handler: () => void): () => void {
    return useDeeplinkStore.subscribe((s, prev) => {
        if (s.mailNonce !== prev.mailNonce) handler();
    });
}

export function isBusinessesTarget(value: unknown): value is BusinessesTarget {
    if (typeof value !== 'object' || value === null || Array.isArray(value)) return false;
    const route = Reflect.get(value, 'route');
    const entityType = Reflect.get(value, 'entityType');
    const entityId = Reflect.get(value, 'entityId');
    if (route === 'directory' && entityType === 'business') {
        return typeof entityId === 'string' && entityId.trim() !== '';
    }

    const scope = Reflect.get(value, 'scope');
    const thread = Reflect.get(value, 'thread');
    return (scope === 'personal' || scope === 'job') && typeof thread === 'string' && thread.trim() !== '';
}

export function isBusinessesThreadTarget(target: BusinessesTarget | null): target is BusinessesThreadTarget {
    return target !== null && 'thread' in target;
}

export function isBusinessesCompanyTarget(target: BusinessesTarget | null): target is BusinessesCompanyTarget {
    return target !== null && target.route === 'directory';
}

export function requestOpenBusinesses(target: BusinessesTarget): void {
    useDeeplinkStore.setState((s) => ({
        businessesTarget: target,
        businessesNonce: s.businessesNonce + 1,
    }));
}

export function useBusinessesTarget(): BusinessesTarget | null {
    useDeeplinkStore((s) => s.businessesNonce);
    return useDeeplinkStore((s) => s.businessesTarget);
}

export function useBusinessesNonce(): number {
    return useDeeplinkStore((s) => s.businessesNonce);
}

export function clearBusinessesTarget(): void {
    useDeeplinkStore.setState({ businessesTarget: null });
}
