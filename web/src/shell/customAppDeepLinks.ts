type CustomAppDeepLink = Record<string, unknown>;
type CustomAppDeepLinkListener = (link: CustomAppDeepLink) => void;

const listeners = new Map<string, Set<CustomAppDeepLinkListener>>();
const pendingLinks = new Map<string, CustomAppDeepLink>();

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
