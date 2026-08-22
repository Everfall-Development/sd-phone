import { useRef, useState } from 'react';
import { ArrowUp, Images, LoaderCircle, MapPin, X } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';

import { isFiveM } from '@/core/nui';
import { apiData } from '@/core/api';
import { t } from '@/i18n';
import { AlertDialog } from '@/ui/AlertDialog';
import { encodeWaypoint } from '@/lib/waypointCode';
import { EmojiPanel } from '@/shared/chat/EmojiPanel';
import { MediaPickerSheet } from '@/shared/MediaPickerSheet';
import { warmPhotos } from '@/core/photosApi';
import { buildServiceDrafts, limitServiceAttachments, type ServiceSendFeedback } from './messageData';
import type { ServiceDraft } from './servicesApi';

type Panel = 'emoji' | null;

type ActionButton = {
    id: 'emoji' | 'photos' | 'location';
    emoji?: string;
    Icon?: LucideIcon;
};

const ACTION_BUTTONS: readonly ActionButton[] = [
    { id: 'emoji', emoji: '😊' },
    { id: 'photos', Icon: Images },
    { id: 'location', Icon: MapPin },
];

export function ServiceComposer({ isDark, onSend, sending = false }: {
    isDark: boolean;
    onSend: (drafts: ServiceDraft[]) => Promise<ServiceSendFeedback>;
    sending?: boolean;
}) {
    const [draft,       setDraft]       = useState('');
    const [panel,       setPanel]       = useState<Panel>(null);
    const [attachments, setAttachments] = useState<string[]>([]);
    const [picking,     setPicking]     = useState(false);
    const [confirmLocation, setConfirmLocation] = useState(false);
    const [submitting,  setSubmitting]  = useState(false);
    const [error,       setError]       = useState<string | null>(null);
    const inputRef = useRef<HTMLInputElement>(null);

    const isSending = submitting || sending;

    function togglePanel(p: Panel) { setPanel(prev => (prev === p ? null : p)); inputRef.current?.blur(); }
    function openPhotos()        { warmPhotos(); setPicking(true); setPanel(null); inputRef.current?.blur(); }
    function openShareLocation() { setConfirmLocation(true); setPanel(null); inputRef.current?.blur(); }

    async function deliver(drafts: ServiceDraft[]): Promise<boolean> {
        try {
            const result = await onSend(drafts);
            if (!result.success) {
                setError(result.message ?? t('services.couldntSend', "Couldn't send your message."));
                return false;
            }
            return true;
        } catch {
            setError(t('services.couldntSend', "Couldn't send your message."));
            return false;
        }
    }

    async function submit(drafts: ServiceDraft[]) {
        if (isSending || drafts.length === 0) return;
        const submittedDraft = draft;
        const submittedAttachments = attachments;
        setSubmitting(true);
        setError(null);
        setPanel(null);
        try {
            const sent = await deliver(drafts);
            if (!sent) return;

            setDraft(current => {
                if (current === submittedDraft) return '';
                if (submittedDraft && current.startsWith(submittedDraft)) {
                    return current.slice(submittedDraft.length).trimStart();
                }
                return current;
            });
            setAttachments(current =>
                current.length === submittedAttachments.length
                && current.every((url, index) => url === submittedAttachments[index])
                    ? []
                    : current,
            );
            window.requestAnimationFrame(() => inputRef.current?.focus());
        } finally {
            setSubmitting(false);
        }
    }

    function sendText() {
        void submit(buildServiceDrafts(draft, attachments, t('services.photoLabel', '📷 Photo')));
    }

    function removeAttachment(url: string) {
        setError(null);
        setAttachments(prev => prev.filter(attachment => attachment !== url));
    }

    function handleKey(e: React.KeyboardEvent) {
        if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); sendText(); }
    }

    async function shareLocation() {
        if (isSending) return;
        setConfirmLocation(false);
        setSubmitting(true);
        setError(null);
        try {
            const locationDraft: ServiceDraft = {
                kind: 'location',
                body: t('services.currentLocation', 'Current Location'),
            };

            if (isFiveM) {
                const current = await apiData<{ x: number; y: number }>('sd-phone:maps:here');
                if (!current) {
                    setError(t('services.couldntShareLocation', "Couldn't share your location."));
                    return;
                }
                locationDraft.wpCode = encodeWaypoint({
                    label: t('services.sharedLocation', 'Shared Location'),
                    x: current.x,
                    y: current.y,
                    icon: 'MapPin',
                    color: '#eb4b3c',
                });
                locationDraft.wpSub = `${Math.round(current.x)}, ${Math.round(current.y)}`;
            }

            await deliver([locationDraft]);
        } catch {
            if (isFiveM) {
                setError(t('services.couldntShareLocation', "Couldn't share your location."));
            } else {
                setError(t('services.couldntSend', "Couldn't send your message."));
            }
        } finally {
            setSubmitting(false);
        }
    }

    const hasContent = draft.trim().length > 0 || attachments.length > 0;

    const trayBg = isDark ? 'rgb(var(--surface))' : 'rgb(var(--base))';
    const pillBg = isDark ? 'rgb(var(--elevated))' : 'rgb(var(--surface))';
    const pillBdr = isDark ? 'rgba(255,255,255,0.13)' : 'rgba(0,0,0,0.13)';
    const controlFocus = 'focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-inset focus-visible:ring-black/35 dark:focus-visible:ring-white/45';
    return (
        <div className="relative shrink-0" aria-busy={isSending}>
            {panel === 'emoji' && (
                <div className="absolute inset-x-0 bottom-full z-20">
                    <EmojiPanel isDark={isDark} onSelect={e => setDraft(d => d + e)} />
                </div>
            )}

            {attachments.length > 0 && (
                <div className="flex flex-wrap gap-2 px-4 pb-1 pt-2">
                    {attachments.map(url => (
                        <div key={url} className="relative">
                            <img src={url} alt="" draggable={false} className="h-[85px] w-[85px] rounded-[12px] object-cover" />
                            <button
                                type="button"
                                onClick={() => removeAttachment(url)}
                                aria-label={t('services.removeImage', 'Remove image')}
                                disabled={isSending}
                                className={`absolute right-1 top-1 flex h-[20px] w-[20px] items-center justify-center rounded-full bg-black/55 active:opacity-70 ${controlFocus}`}
                            >
                                <X className="h-[12px] w-[12px] text-white" strokeWidth={2.75} />
                            </button>
                        </div>
                    ))}
                </div>
            )}

            <div className="px-3 pb-2 pt-1.5">
                <div
                    className={`flex items-center gap-1 rounded-[22px] border border-black/[0.13] py-[9px] pl-4 transition-colors focus-within:border-black/35 dark:border-white/[0.13] dark:focus-within:border-white/35 ${hasContent ? 'pr-[5px]' : 'pr-4'}`}
                    style={{ background: pillBg }}
                >
                    <input
                        ref={inputRef}
                        type="text"
                        value={draft}
                        onChange={e => { setDraft(e.target.value); setError(null); }}
                        onKeyDown={handleKey}
                        onFocus={() => setPanel(null)}
                        placeholder={t('services.messagePlaceholder', 'Message')}
                        aria-label={t('services.messagePlaceholder', 'Message')}
                        aria-describedby={error ? 'services-message-error' : undefined}
                        aria-invalid={error ? true : undefined}
                        maxLength={300}
                        className="min-w-0 flex-1 bg-transparent py-[5px] text-[18px] text-black placeholder-black/35 outline-none focus-visible:!outline-none dark:text-white dark:placeholder-white/35"
                    />
                    {hasContent && (
                        <button
                            type="button"
                            onClick={sendText}
                            onMouseDown={(event) => event.preventDefault()}
                            aria-label={t('services.send', 'Send')}
                            disabled={isSending}
                            className={`flex h-[33px] w-[33px] shrink-0 items-center justify-center rounded-full bg-black text-white active:opacity-70 disabled:opacity-50 dark:bg-white dark:text-black ${controlFocus}`}
                        >
                            {isSending
                                ? <LoaderCircle className="h-[18px] w-[18px] animate-spin" strokeWidth={2.75} />
                                : <ArrowUp className="h-[19px] w-[19px]" strokeWidth={2.75} />}
                        </button>
                    )}
                </div>
            </div>

            {error && (
                <div id="services-message-error" role="alert" className="px-4 pb-1 text-[14px] font-medium text-ios-red">
                    {error}
                </div>
            )}

            <div
                className="flex items-center justify-around px-4 pb-11 pt-2.5"
                style={{ background: trayBg, borderTop: `0.5px solid ${pillBdr}` }}
            >
                {ACTION_BUTTONS.map(btn => {
                    const Icon = btn.Icon;
                    const label = btn.id === 'photos'
                        ? t('services.photos', 'Photos')
                        : btn.id === 'location'
                            ? t('services.location', 'Location')
                            : t('services.emoji', 'Emoji');
                    return (
                        <button
                            key={btn.id}
                            type="button"
                            onClick={() => (btn.id === 'photos' ? openPhotos() : btn.id === 'location' ? openShareLocation() : togglePanel('emoji'))}
                            aria-label={label}
                            disabled={isSending}
                            className={`flex h-[44px] w-[52px] items-center justify-center rounded-[12px] text-black/65 transition-colors active:bg-black/[0.07] disabled:opacity-40 dark:text-white/70 dark:active:bg-white/[0.09] ${controlFocus}`}
                        >
                            {Icon ? (
                                <Icon
                                    className={btn.id === 'location' ? 'h-[26px] w-[26px]' : 'h-[25px] w-[25px]'}
                                    strokeWidth={2}
                                />
                            ) : (
                                <span className="text-[23px] leading-none">{btn.emoji}</span>
                            )}
                        </button>
                    );
                })}
            </div>

            {picking && (
                <MediaPickerSheet
                    multiple
                    forceDark={isDark}
                    onSelectMany={ps => {
                        const selected = ps.map(p => p.url);
                        const selection = limitServiceAttachments(attachments, selected);
                        setAttachments(prev => [...prev, ...selection.accepted]);
                        setError(selection.dropped > 0
                            ? t('services.maxImages', 'You can send up to four images at once.')
                            : null);
                        setPicking(false);
                    }}
                    onClose={() => setPicking(false)}
                />
            )}

            {confirmLocation && (
                <AlertDialog
                    title={t('services.shareLocation', 'Share Location')}
                    message={t('services.shareLocationMsg', 'Are you sure you want to share your location?')}
                    cancelLabel={t('services.cancel', 'Cancel')}
                    confirmLabel={t('services.share', 'Share')}
                    forceDark={isDark}
                    onCancel={() => setConfirmLocation(false)}
                    onConfirm={() => { void shareLocation(); }}
                />
            )}
        </div>
    );
}
