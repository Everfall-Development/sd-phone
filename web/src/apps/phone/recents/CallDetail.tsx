import { useState } from 'react';
import type { ReactNode } from 'react';
import { Check, ChevronLeft, Copy, MessageSquare, Phone, Share, Video } from 'lucide-react';

import { device } from '@device';
import { copyToClipboard } from '@/lib/clipboard';
import { colorFor, initialsFor } from '@/lib/format';
import { useIosPush } from '@/hooks/useIosPush';
import { requestOpenMessages } from '@/shell/deeplink';
import { ContactAvatar, InitialsAvatar, PlaceholderAvatar } from '@/shared/ContactAvatar';
import { ShareAction, ShareSheet } from '@/shared/ShareSheet';
import { callEntryTitle, isBusinessNumber, isDialableCallEntry, type CallEntry, type Contact } from '../data';
import { shareContactApi } from '../contactsApi';
import { useMaskedPhone } from '@/stores/themeStore';
import { t } from '@/i18n';

export function CallDetail({ entry, onBack, onAddToContacts, onRequestCall }: {
    entry:           CallEntry;
    onBack:          () => void;
    onAddToContacts: () => void;
    onRequestCall:   (target: { number: string; name?: string; video?: boolean }) => void;
}) {
    const [sharing, setSharing] = useState(false);
    const [copied, setCopied] = useState(false);
    const phone = useMaskedPhone();
    const { goBack, pageStyle, animating } = useIosPush(onBack);

    const isPlainNumber = !entry.contact && !entry.name?.trim() && !entry.noCallerId && !isBusinessNumber(entry.number);
    const title = isPlainNumber ? phone(entry.number) : callEntryTitle(entry);
    const hasNamedCaller = Boolean(entry.name?.trim()) || isBusinessNumber(entry.number);
    const hasDialableNumber = isDialableCallEntry(entry);

    function shareCard(): Contact {
        if (entry.contact) return entry.contact;
        return {
            id: entry.id,
            name: title,
            initials: initialsFor(title),
            color: colorFor(title),
            phone: entry.number,
        };
    }

    return (
        <div
            className="absolute inset-0 flex flex-col bg-base"
            inert={animating}
            aria-hidden={animating}
            style={{ ...pageStyle, willChange: pageStyle.animation ? 'transform' : undefined }}
        >
            <div className="flex items-center px-3 py-2">
                <button type="button" onClick={goBack} className="flex items-center text-ios-blue active:opacity-60">
                    <ChevronLeft className="h-[28px] w-[28px]" strokeWidth={2.4} />
                    <span className="-ml-0.5 text-[18px]">{t('phone.recents','Recents')}</span>
                </button>
            </div>

            <div className="flex-1 overflow-y-auto no-scrollbar px-4 pb-6">
                <div className="flex flex-col items-center pb-5 pt-1">
                    {entry.contact ? <ContactAvatar contact={entry.contact} size={134} /> : hasNamedCaller ? <InitialsAvatar name={title} color="#8e8e93" size={134} /> : <PlaceholderAvatar size={134} />}
                    <div className="mt-3 text-center text-[30px] font-semibold text-black dark:text-white">{title}</div>
                </div>

                {hasDialableNumber && (
                    <div className="mb-7 flex gap-3">
                        <ActionButton
                            label={t('phone.actionMessage','message')}
                            onClick={() => requestOpenMessages({ number: entry.number, name: title })}
                            icon={<MessageSquare className="h-[28px] w-[28px]" strokeWidth={2} fill="currentColor" />}
                        />
                        {device.calls && (
                            <ActionButton
                                label={t('phone.actionCall','call')}
                                onClick={() => onRequestCall({ number: entry.number, name: title })}
                                icon={<Phone className="h-[28px] w-[28px]" strokeWidth={2} fill="currentColor" />}
                            />
                        )}
                        {device.calls && (
                            <ActionButton
                                label={t('phone.actionVideo','video')}
                                onClick={() => onRequestCall({ number: entry.number, name: title, video: true })}
                                icon={<Video className="h-[28px] w-[28px]" strokeWidth={2} fill="currentColor" />}
                            />
                        )}
                        <ActionButton
                            label={t('phone.actionShare','share')}
                            onClick={() => setSharing(true)}
                            icon={<Share className="h-[28px] w-[28px]" strokeWidth={2} />}
                        />
                    </div>
                )}

                <div className="mb-4 rounded-[10px] bg-surface px-4 py-3">
                    <div className="text-[15px] font-semibold text-black dark:text-white">{entry.date}</div>
                    <div className="mt-0.5 flex items-center gap-2 text-[15px] text-black/60 dark:text-white/60">
                        <span>{entry.timeOfDay}</span>
                        <span>{entry.direction}</span>
                    </div>
                    {entry.duration && <div className="mt-0.5 text-[13px] text-black/45 dark:text-white/45">{entry.duration}</div>}
                </div>

                {hasDialableNumber && (
                    <>
                        <div className="mb-4 rounded-[10px] bg-surface px-4 py-3">
                            <div className="text-[13px] text-black/50 dark:text-white/50">{t('phone.phoneLabel','phone')}</div>
                            <div className="text-[19px] text-ios-blue">{phone(entry.number)}</div>
                        </div>
                        {!entry.contact && (
                            <button
                                type="button"
                                onClick={onAddToContacts}
                                className="w-full rounded-[10px] bg-surface px-4 py-3.5 text-left text-[19px] text-ios-blue active:bg-black/5 dark:active:bg-white/5"
                            >
                                {t('phone.addToContacts','Add to Contacts')}
                            </button>
                        )}
                    </>
                )}
            </div>

            {sharing && (
                <ShareSheet
                    onClose={() => { setSharing(false); setCopied(false); }}
                    onShare={target => shareContactApi(target.id, shareCard())}
                >
                    <ShareAction
                        icon={copied
                            ? <Check className="h-[23px] w-[23px]" strokeWidth={2.3} />
                            : <Copy className="h-[23px] w-[23px]" strokeWidth={2} />}
                        label={copied ? t('phone.copiedBang','Copied!') : t('phone.copyNumberTitle','Copy Number')}
                        onClick={() => {
                            copyToClipboard(entry.number);
                            setCopied(true);
                            window.setTimeout(() => setCopied(false), 1600);
                        }}
                    />
                </ShareSheet>
            )}
        </div>
    );
}

function ActionButton({ icon, label, onClick }: { icon: ReactNode; label: string; onClick: () => void }) {
    return (
        <button
            type="button"
            onClick={onClick}
            className="flex flex-1 flex-col items-center gap-2 rounded-[12px] bg-surface py-4 text-ios-blue active:opacity-70 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ios-blue"
        >
            {icon}
            <span className="text-[13px] font-medium">{label}</span>
        </button>
    );
}
