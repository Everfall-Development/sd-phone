type CustomAppDeepLink = Record<string, unknown>;
type CustomAppDeepLinkListener = (link: CustomAppDeepLink) => void;
type CustomAppMessageListener = (message: unknown) => void;

const listeners = new Map<string, Set<CustomAppDeepLinkListener>>();
const pendingLinks = new Map<string, CustomAppDeepLink>();

function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === 'object' && value !== null;
}

export function isCustomAppDeepLinkMessage(message: unknown): boolean {
    return isRecord(message) && message.action === 'deepLink' && isRecord(message.data);
}

export function deliverReadyDeepLinks(
    messages: unknown[],
    deliver: CustomAppMessageListener,
): unknown[] {
    const remaining: unknown[] = [];

    for (const message of messages) {
        if (isCustomAppDeepLinkMessage(message)) {
            deliver(message);
            continue;
        }

        remaining.push(message);
    }

    return remaining;
}

export function publishCustomAppDeepLink(appId: string, link: CustomAppDeepLink): void {
    const appListeners = listeners.get(appId);
    if (!appListeners?.size) {
        pendingLinks.set(appId, link);
        return;
    }

    for (const listener of appListeners) listener(link);
}

export function subscribeCustomAppDeepLink(appId: string, listener: CustomAppDeepLinkListener): () => void {
    const appListeners = listeners.get(appId) ?? new Set<CustomAppDeepLinkListener>();
    appListeners.add(listener);
    listeners.set(appId, appListeners);

    const pendingLink = pendingLinks.get(appId);
    if (pendingLink) {
        pendingLinks.delete(appId);
        listener(pendingLink);
    }

    return () => {
        appListeners.delete(listener);
        if (appListeners.size === 0) listeners.delete(appId);
    };
}
