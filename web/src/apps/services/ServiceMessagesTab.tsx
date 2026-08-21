import { useCallback, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { ChevronLeft, ChevronRight, MessageSquare, RotateCcw, Search } from 'lucide-react';

import { fetchNui, isFiveM } from '@/core/nui';
import { formatClockTime, formatListDate } from '@/lib/time';
import { requestOpenMaps } from '@/shell/deeplink';
import type { BusinessesThreadTarget } from '@/shell/deeplink';
import { t } from '@/i18n';
import { useIosPush } from '@/hooks/useIosPush';
import { useReanimateOnChange } from '@/hooks/useReanimateOnChange';
import { useSessionState } from '@/hooks/useSessionState';
import { useMaskedPhone, useTheme } from '@/stores/themeStore';
import { ActionSheet } from '@/ui/ActionSheet';
import { AlertDialog } from '@/ui/AlertDialog';
import { ImageLightbox } from '@/ui/ImageLightbox';
import { EmptyState } from '@/ui/EmptyState';
import { SegmentedControl } from '@/ui/SegmentedControl';
import { SearchBar } from '@/ui/SearchBar';
import { portalToPhoneScreen } from '@/ui/portal';
import { MessageBubble } from '@/shared/chat/MessageBubble';
import { useAutoScrollToEnd } from '@/shared/chat/useAutoScrollToEnd';
import { fmtChatSeparator, type Message } from '@/shared/chat/data';
import { decodeWaypoint } from '@/lib/waypointCode';
import { apiSavePhotoFromUrl } from '@/core/photosApi';
import { ServiceAvatar } from './ServiceAvatar';
import { ServiceComposer } from './ServiceComposer';
import {
    messageCompany,
    replyCompany,
    type Inbox,
    type InboxMessage,
    type InboxThread,
    type ServiceDraft,
    type ServiceMessageResult,
} from './servicesApi';
import {
    filterMessageThreads,
    getThreadIdentity,
    isNewMessageDay,
    type MessageScope,
    type ServiceSendFeedback,
} from './messageData';

type Scope = MessageScope;

function clock(ts: number): string {
    return formatClockTime(new Date(ts), true);
}

function openMessageInMaps(message: InboxMessage) {
    const waypoint = message.wpCode ? decodeWaypoint(message.wpCode) : null;
    if (!waypoint) return;
    requestOpenMaps({
        label: waypoint.label,
        x: waypoint.x,
        y: waypoint.y,
        icon: waypoint.icon,
        color: waypoint.color,
    });
}

function setMessageWaypoint(message: InboxMessage) {
    const waypoint = message.wpCode ? decodeWaypoint(message.wpCode) : null;
    if (!waypoint) return;
    void fetchNui('sd-phone:maps:waypoint', { x: waypoint.x, y: waypoint.y });
}

export function ServiceMessagesTab({
    inbox,
    loaded,
    loading,
    unavailable,
    onRetry,
    onInboxChange,
    onMarkRead,
    target,
    targetNonce,
    onTargetDismiss,
}: {
    inbox: Inbox;
    loaded: boolean;
    loading: boolean;
    unavailable?: string;
    onRetry?: () => void;
    onInboxChange: (inbox: Inbox) => void;
    onMarkRead: (scope: Scope, key: string) => void;
    target: BusinessesThreadTarget | null;
    targetNonce: number;
    onTargetDismiss: () => void;
}) {
    const [scopePref, setScope] = useSessionState<Scope>('services:msgFilter', 'personal');
    const [query, setQuery] = useSessionState('services:inboxSearch', '');
    const [openKey, setOpenKey] = useState<string | null>(null);

    const targetScope = target?.scope === 'personal' || (target?.scope === 'job' && inbox.hasJob) ? target.scope : null;
    const scope: Scope = targetScope ?? (inbox.hasJob ? scopePref : 'personal');
    const threads = scope === 'personal' ? inbox.personal : inbox.job;
    const visibleThreads = useMemo(() => filterMessageThreads(threads, query), [query, threads]);
    const inboxError = unavailable ?? inbox.unavailable;

    const personalUnread = inbox.personal.some((t) => (t.unread ?? 0) > 0);
    const jobUnread = inbox.job.some((t) => (t.unread ?? 0) > 0);

    const scopeRef = useReanimateOnChange<HTMLDivElement>('animate-swipe-in-left', scope);
    const targetedThread =
        target && target.scope === scope ? (threads.find((thread) => thread.key === target.thread) ?? null) : null;
    const openThread = targetedThread ?? (openKey ? (threads.find((t) => t.key === openKey) ?? null) : null);
    const handledTargetNonce = useRef(0);

    useLayoutEffect(() => {
        if (!target || !loaded || loading || handledTargetNonce.current === targetNonce) return;
        handledTargetNonce.current = targetNonce;

        const validScope = target.scope === 'personal' || inbox.hasJob;
        const targetThreads = target.scope === 'job' ? inbox.job : inbox.personal;
        const threadExists = targetThreads.some((thread) => thread.key === target.thread);
        if (!validScope || inboxError || !threadExists) {
            onTargetDismiss();
            return;
        }

        onMarkRead(target.scope, target.thread);
    }, [
        inbox.hasJob,
        inbox.job,
        inbox.personal,
        inboxError,
        loaded,
        loading,
        onMarkRead,
        onTargetDismiss,
        target,
        targetNonce,
    ]);

    function openThreadByKey(key: string) {
        onMarkRead(scope, key);
        setOpenKey(key);
    }

    function retryInbox() {
        onRetry?.();
    }

    return (
        <div className="relative flex min-h-0 flex-1 flex-col">
            <h1 className="select-none px-5 pb-2 pt-1 text-[34px] font-bold tracking-tight text-black dark:text-white">
                {t('services.inbox', 'Inbox')}
            </h1>

            <div>
                <SearchBar
                    value={query}
                    onChange={setQuery}
                    placeholder={t('services.searchMessages', 'Search messages')}
                    className="mx-4 mb-3"
                />
            </div>

            {inbox.hasJob && (
                <div
                    className="select-none px-4 pb-3"
                    role="group"
                    aria-label={t('services.messageScope', 'Message scope')}
                >
                    <SegmentedControl
                        value={scope}
                        onChange={setScope}
                        options={[
                            { value: 'personal', label: t('services.personal', 'Personal'), dot: personalUnread },
                            { value: 'job', label: t('services.job', 'Job'), dot: jobUnread },
                        ]}
                        className="mx-auto w-[232px]"
                    />
                </div>
            )}

            <div className="min-h-0 flex-1 select-none overflow-y-auto no-scrollbar px-4 pb-6">
                <div ref={scopeRef}>
                    {!loaded ? (
                        <InboxLoading />
                    ) : inboxError ? (
                        <EmptyState
                            icon={MessageSquare}
                            title={t('services.inboxUnavailableTitle', 'Inbox Unavailable')}
                            subtitle={inboxError}
                            action={
                                <button
                                    type="button"
                                    onClick={retryInbox}
                                    disabled={loading}
                                    aria-busy={loading}
                                    className="inline-flex items-center gap-2 rounded-[12px] bg-ios-blue px-5 py-3 text-[15px] font-semibold text-white active:opacity-70 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ios-blue focus-visible:ring-offset-2 disabled:opacity-60"
                                >
                                    <RotateCcw className="h-4 w-4" aria-hidden="true" />
                                    {loading
                                        ? t('services.retrying', 'Retrying…')
                                        : t('services.tryAgain', 'Try Again')}
                                </button>
                            }
                        />
                    ) : visibleThreads.length === 0 && (threads.length > 0 || query.trim()) ? (
                        <EmptyState
                            icon={Search}
                            title={t('services.noMessageMatches', 'No Matches')}
                            circle={false}
                            action={
                                <button
                                    type="button"
                                    onClick={() => setQuery('')}
                                    className="text-[16px] font-semibold text-ios-blue active:opacity-65 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ios-blue focus-visible:ring-offset-2"
                                >
                                    {t('services.clearSearch', 'Clear Search')}
                                </button>
                            }
                        />
                    ) : threads.length === 0 ? (
                        <EmptyState icon={MessageSquare} title={t('services.noMessages', 'No Messages')} />
                    ) : (
                        <div className="overflow-hidden rounded-[12px] bg-surface">
                            {visibleThreads.map((thread, i) => (
                                <div key={thread.key}>
                                    <ThreadRow
                                        thread={thread}
                                        scope={scope}
                                        onOpen={() => openThreadByKey(thread.key)}
                                    />
                                    {i < visibleThreads.length - 1 && (
                                        <div
                                            className="pointer-events-none bg-black/10 dark:bg-white/10"
                                            style={{ height: '0.5px' }}
                                        />
                                    )}
                                </div>
                            ))}
                        </div>
                    )}
                </div>
            </div>

            {openThread && (
                <Conversation
                    key={openThread.key}
                    scope={scope}
                    thread={openThread}
                    onBack={() => {
                        setOpenKey(null);
                        if (targetedThread) onTargetDismiss();
                    }}
                    onSent={onInboxChange}
                />
            )}
        </div>
    );
}

function InboxLoading() {
    return (
        <div
            role="status"
            aria-label={t('services.loadingMessages', 'Loading messages')}
            aria-busy="true"
            className="overflow-hidden rounded-[12px] bg-surface"
        >
            {[0, 1, 2].map((index) => (
                <div key={index} className="flex items-center gap-4 px-4 py-4">
                    <div className="h-[58px] w-[58px] shrink-0 animate-pulse rounded-full bg-black/[0.08] dark:bg-white/[0.10]" />
                    <div className="min-w-0 flex-1 space-y-2">
                        <div className="h-4 w-2/5 animate-pulse rounded-full bg-black/[0.08] dark:bg-white/[0.10]" />
                        <div className="h-4 w-4/5 animate-pulse rounded-full bg-black/[0.08] dark:bg-white/[0.10]" />
                    </div>
                </div>
            ))}
        </div>
    );
}

function ThreadRow({ thread, scope, onOpen }: { thread: InboxThread; scope: Scope; onOpen: () => void }) {
    const phone = useMaskedPhone();
    const identity = getThreadIdentity(thread, scope, phone);
    const unread = (thread.unread ?? 0) > 0;
    const unreadCount = Math.max(thread.unread ?? 0, 0);
    const unreadText = unreadCount > 99 ? '99+' : String(unreadCount);
    const rowLabel = t('services.openConversation', 'Open conversation with {name}', {
        name: identity.title,
    });
    return (
        <button
            type="button"
            onClick={onOpen}
            aria-label={
                unread
                    ? `${rowLabel}. ${t('services.unreadCount', '{count} unread', { count: unreadCount })}`
                    : rowLabel
            }
            className="flex w-full items-center gap-4 px-4 py-4 text-left active:bg-black/5 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ios-blue dark:active:bg-white/5"
        >
            <ServiceAvatar emoji={thread.emoji} iconUrl={thread.iconUrl} size={58} />

            <div className="min-w-0 flex-1">
                <div className="truncate text-[20px] font-semibold text-black dark:text-white">{identity.title}</div>
                {identity.secondary && (
                    <div className="mt-0.5 truncate text-[15px] font-medium text-black/55 dark:text-white/55">
                        {identity.secondary}
                    </div>
                )}
                <div
                    className={`mt-1 line-clamp-2 text-[17px] leading-snug ${unread ? 'font-semibold text-black dark:text-white' : 'font-medium text-black/90 dark:text-white/85'}`}
                >
                    {thread.preview}
                </div>
            </div>

            <div className="flex shrink-0 flex-col items-end gap-1.5 self-start pt-0.5">
                <span className="text-[15px] font-medium text-black/70 dark:text-white/60">
                    {formatListDate(thread.ts)}
                </span>
                {unread ? (
                    <span
                        aria-hidden="true"
                        className="flex min-h-[20px] min-w-[20px] items-center justify-center rounded-full bg-ios-blue px-1 text-[12px] font-bold leading-none text-white"
                    >
                        {unreadText}
                    </span>
                ) : (
                    <ChevronRight className="h-[18px] w-[18px] text-black/25 dark:text-white/25" strokeWidth={2.5} />
                )}
            </div>
        </button>
    );
}

function toBubbleMsg(m: InboxMessage): Message {
    return {
        id: m.id,
        from: m.from === 'me' ? 'me' : 'them',
        body: m.body,
        kind: m.kind ?? 'text',
        ts: m.ts,
        read: true,
        gifUrl: m.mediaUrl,
        wpCode: m.wpCode,
        wpSub: m.wpSub,
    };
}

function Conversation({
    scope,
    thread,
    onBack,
    onSent,
}: {
    scope: Scope;
    thread: InboxThread;
    onBack: () => void;
    onSent: (inbox: Inbox) => void;
}) {
    const { theme } = useTheme('theme');
    const phone = useMaskedPhone();
    const isDark = theme === 'dark';
    const [sending, setSending] = useState(false);
    const [locSheet, setLocSheet] = useState<InboxMessage | null>(null);
    const [preview, setPreview] = useState<string | null>(null);
    const [savedPreview, setSavedPreview] = useState(false);
    const [savingPreview, setSavingPreview] = useState(false);
    const [saveError, setSaveError] = useState<string | null>(null);
    const listRef = useRef<HTMLDivElement>(null);
    const { goBack, pageStyle, animating } = useIosPush(onBack);
    const identity = getThreadIdentity(thread, scope, phone);

    useAutoScrollToEnd(listRef, thread.messages.length);

    async function handleSend(drafts: ServiceDraft[]): Promise<ServiceSendFeedback> {
        if (sending) return { success: false, message: t('services.pleaseWait', 'Please wait a moment.') };
        setSending(true);
        try {
            const result: ServiceMessageResult =
                scope === 'personal'
                    ? await messageCompany(thread.key, drafts)
                    : await replyCompany(thread.key, drafts);
            if (!result.success) {
                return {
                    success: false,
                    message: result.message ?? t('services.couldntSend', "Couldn't send your message."),
                };
            }
            if (result.data?.inbox) onSent(result.data.inbox);
            return { success: true };
        } catch {
            return { success: false, message: t('services.couldntSend', "Couldn't send your message.") };
        } finally {
            setSending(false);
        }
    }

    const bubbleMsgs = useMemo(() => thread.messages.map(toBubbleMsg), [thread.messages]);
    const noop = useCallback(() => {}, []);
    const handleImageTap = useCallback((url: string) => {
        setPreview(url);
        setSavedPreview(false);
    }, []);
    const handleLocationTap = useCallback(
        (id: string) => {
            const m = thread.messages.find((x) => x.id === id);
            if (m?.wpCode && decodeWaypoint(m.wpCode)) setLocSheet(m);
        },
        [thread.messages],
    );

    function openInMaps(message: InboxMessage) {
        onBack();
        openMessageInMaps(message);
    }

    async function savePreviewToGallery() {
        if (!preview || savedPreview || savingPreview) return;
        setSavingPreview(true);
        setSaveError(null);
        try {
            const result = await apiSavePhotoFromUrl(preview);
            if (result.ok) {
                setSavedPreview(true);
                return;
            }
            setSaveError(result.message ?? t('services.couldntSavePhoto', "Couldn't save the photo."));
        } catch {
            setSaveError(t('services.couldntSavePhoto', "Couldn't save the photo."));
        } finally {
            setSavingPreview(false);
        }
    }

    const receivedBg = isDark ? 'rgb(var(--elevated))' : 'rgb(var(--control))';
    const sentBg = 'rgb(var(--ios-blue))';

    const view = (
        <div
            className={`absolute inset-0 z-20 flex min-h-0 flex-col bg-surface font-sf dark:bg-base ${isDark ? 'dark' : ''}`}
            inert={animating}
            aria-hidden={animating}
            style={{ ...pageStyle, willChange: pageStyle.animation ? 'transform' : undefined }}
        >
            <div className="h-[58px] shrink-0" aria-hidden />

            <div className="select-none flex items-center px-2 pb-2.5 pt-0.5">
                <div className="flex flex-1 items-center">
                    <button
                        type="button"
                        onClick={goBack}
                        aria-label={t('services.back', 'Back')}
                        className="flex items-center text-ios-blue active:opacity-60 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ios-blue focus-visible:ring-inset"
                    >
                        <ChevronLeft className="h-[34px] w-[34px]" strokeWidth={2.4} />
                    </button>
                </div>
                <div className="flex min-w-0 flex-col items-center gap-1.5">
                    <ServiceAvatar emoji={thread.emoji} iconUrl={thread.iconUrl} size={64} />
                    <span className="max-w-[200px] truncate text-[18px] font-semibold leading-none text-black dark:text-white">
                        {identity.title}
                    </span>
                    {identity.secondary && (
                        <span className="max-w-[200px] truncate text-[13px] font-medium leading-none text-black/55 dark:text-white/55">
                            {identity.secondary}
                        </span>
                    )}
                </div>
                <div className="flex-1" />
            </div>

            <div ref={listRef} className="min-h-0 flex-1 overflow-y-auto no-scrollbar">
                <div className="flex min-h-full flex-col justify-end px-3 py-3">
                    {thread.messages.map((m, i) => {
                        const prev = thread.messages[i - 1];
                        const next = thread.messages[i + 1];
                        const sent = m.from === 'me';
                        const isLast = !next || next.from !== m.from;
                        const showName =
                            !sent && scope !== 'job' && (!prev || prev.from !== m.from || prev.name !== m.name);
                        const showDay = isNewMessageDay(prev, m);
                        const separator = showDay ? fmtChatSeparator(m.ts) : null;
                        return (
                            <div key={m.id}>
                                {separator && (
                                    <div className="flex justify-center pb-3 pt-4">
                                        <span className="text-[13px] tracking-wide text-black/40 dark:text-white/40">
                                            <span className="font-semibold text-black/55 dark:text-white/55">
                                                {separator.lead}
                                            </span>{' '}
                                            {separator.time}
                                        </span>
                                    </div>
                                )}
                                <div
                                    className={`flex ${isLast ? 'mb-3' : 'mb-[2px]'} ${sent ? 'justify-end' : 'justify-start'}`}
                                >
                                    <div
                                        className={`flex flex-col ${sent ? 'max-w-[78%] items-end' : 'max-w-[80%] items-start'}`}
                                    >
                                        {showName && m.name && (
                                            <span className="mb-0.5 ml-1 text-[12px] font-semibold text-black/45 dark:text-white/45">
                                                {m.name}
                                            </span>
                                        )}
                                        <MessageBubble
                                            msg={bubbleMsgs[i]}
                                            sent={sent}
                                            isLast={isLast}
                                            isDark={isDark}
                                            receivedBg={receivedBg}
                                            sentBg={sentBg}
                                            hideActions
                                            pickerOpen={false}
                                            onOpenPicker={noop}
                                            onReact={noop}
                                            onReply={noop}
                                            onPay={noop}
                                            onLocationTap={handleLocationTap}
                                            onImageTap={handleImageTap}
                                            locationCaption={
                                                m.kind === 'location'
                                                    ? sent
                                                        ? t('services.youSharedLocation', 'You shared your location')
                                                        : t('services.sharedALocation', '{name} shared a location', {
                                                              name: m.name || t('services.they', 'They'),
                                                          })
                                                    : undefined
                                            }
                                        />
                                        {isLast && (
                                            <span className="ml-1 mt-1 text-[11px] text-black/35 dark:text-white/30">
                                                {clock(m.ts)}
                                            </span>
                                        )}
                                    </div>
                                </div>
                            </div>
                        );
                    })}
                </div>
            </div>

            <ServiceComposer isDark={isDark} sending={sending} onSend={handleSend} />

            {locSheet && (
                <ActionSheet
                    forceDark={isDark}
                    actions={[
                        {
                            label: t('services.openInMaps', 'Open in Maps'),
                            onClick: () => openInMaps(locSheet),
                        },
                        ...(isFiveM
                            ? [
                                  {
                                      label: t('services.setWaypoint', 'Set Waypoint'),
                                      onClick: () => setMessageWaypoint(locSheet),
                                  },
                              ]
                            : []),
                    ]}
                    onClose={() => setLocSheet(null)}
                />
            )}

            {preview && (
                <ImageLightbox
                    src={preview}
                    onClose={() => setPreview(null)}
                    action={{
                        label: savedPreview
                            ? t('services.savedToGallery', 'Saved to Gallery')
                            : savingPreview
                              ? t('services.saving', 'Saving…')
                              : t('services.saveToGallery', 'Save to Gallery'),
                        onClick: () => {
                            void savePreviewToGallery();
                        },
                    }}
                />
            )}

            {saveError && (
                <AlertDialog
                    title={t('services.couldntComplete', "Couldn't Complete")}
                    message={saveError}
                    confirmLabel={t('services.ok', 'OK')}
                    hideCancel
                    forceDark={isDark}
                    onCancel={() => setSaveError(null)}
                    onConfirm={() => setSaveError(null)}
                />
            )}
        </div>
    );

    return portalToPhoneScreen(view);
}
