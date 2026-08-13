import { ChevronLeft, ChevronRight, MapPin, MessageSquare, Phone } from 'lucide-react';
import type { ReactNode } from 'react';

import { device } from '@device';
import { useIosPush } from '@/hooks/useIosPush';
import { t } from '@/i18n';
import { portalToPhoneScreen } from '@/ui/portal';
import { ServiceAvatar } from './ServiceAvatar';
import type { Company } from './data';

type BusinessAction = 'call' | 'message' | 'locate';

export function BusinessDetail({ company, pending, onBack, onCall, onMessage, onLocate }: {
    company: Company;
    pending: BusinessAction | null;
    onBack: () => void;
    onCall: () => void;
    onMessage: () => void;
    onLocate: () => void;
}) {
    const { goBack, pageStyle, animating } = useIosPush(onBack);
    const open = company.status === 'open';
    const canCall = device.calls && company.canCall;
    let callLabel = open ? t('services.call', 'Call') : t('services.closed', 'Closed');
    if (pending === 'call') callLabel = t('services.calling', 'Calling…');

    const detail = (
        <div
            className="absolute inset-0 z-30 flex min-h-0 flex-col bg-base font-sf"
            inert={animating}
            aria-hidden={animating}
            style={{ ...pageStyle, willChange: pageStyle.animation ? 'transform' : undefined }}
        >
            <div className="h-[58px] shrink-0" aria-hidden />

            <div className="flex h-11 shrink-0 items-center px-2">
                <button
                    type="button"
                    onClick={goBack}
                    className="flex min-w-0 items-center text-ios-blue active:opacity-60 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ios-blue"
                >
                    <ChevronLeft className="h-[30px] w-[30px] shrink-0" strokeWidth={2.4} />
                    <span className="-ml-0.5 truncate text-[18px]">{t('services.directory', 'Directory')}</span>
                </button>
            </div>

            <div className="min-h-0 flex-1 overflow-y-auto no-scrollbar px-4 pb-10">
                <div className="flex flex-col items-center px-5 pb-7 pt-3 text-center">
                    <ServiceAvatar
                        color={company.color}
                        emoji={company.emoji}
                        iconUrl={company.iconUrl}
                        size={96}
                    />
                    <h1 className="mt-4 max-w-[330px] text-[28px] font-bold leading-tight text-black dark:text-white">
                        {company.name}
                    </h1>
                    <div className="mt-2 flex items-center gap-2 text-[15px] font-medium text-black/55 dark:text-white/55">
                        <span
                            className={`h-2.5 w-2.5 rounded-full ${open ? 'bg-ios-green' : 'bg-ios-gray'}`}
                            aria-hidden
                        />
                        <span>{open ? t('services.open', 'Open') : t('services.closed', 'Closed')}</span>
                        <span aria-hidden>·</span>
                        <span>{company.category}</span>
                    </div>
                </div>

                <div className="mb-5 flex gap-3">
                    {canCall && (
                        <DetailAction
                            label={callLabel}
                            ariaLabel={t('services.callName', 'Call {name}', { name: company.name })}
                            disabled={!open || pending !== null}
                            onClick={onCall}
                        >
                            <Phone className="h-[28px] w-[28px]" strokeWidth={2.1} fill="currentColor" />
                        </DetailAction>
                    )}
                    {company.canMessage && (
                        <DetailAction
                            label={pending === 'message' ? t('services.sending', 'Sending…') : t('services.message', 'Message')}
                            ariaLabel={t('services.messageName', 'Message {name}', { name: company.name })}
                            disabled={pending !== null}
                            onClick={onMessage}
                        >
                            <MessageSquare className="h-[28px] w-[28px]" strokeWidth={2.1} fill="currentColor" />
                        </DetailAction>
                    )}
                    {company.coords && (
                        <DetailAction
                            label={t('services.directions', 'Directions')}
                            ariaLabel={t('services.locateName', 'Locate {name}', { name: company.name })}
                            disabled={pending !== null}
                            onClick={onLocate}
                        >
                            <MapPin className="h-[29px] w-[29px]" strokeWidth={2.2} />
                        </DetailAction>
                    )}
                </div>

                {company.coords && (
                    <button
                        type="button"
                        onClick={onLocate}
                        className="flex w-full items-center gap-3 rounded-[12px] bg-surface px-4 py-4 text-left active:bg-black/[0.06] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ios-blue dark:active:bg-white/[0.08]"
                    >
                        <MapPin className="h-6 w-6 shrink-0 text-ios-blue" strokeWidth={2.1} />
                        <div className="min-w-0 flex-1">
                            <div className="text-[13px] font-medium text-black/50 dark:text-white/50">
                                {t('services.location', 'Location')}
                            </div>
                            <div className="mt-0.5 truncate text-[18px] font-medium text-black dark:text-white">
                                {company.location}
                            </div>
                        </div>
                        <ChevronRight className="h-5 w-5 shrink-0 text-black/25 dark:text-white/25" strokeWidth={2.4} />
                    </button>
                )}
            </div>
        </div>
    );

    return portalToPhoneScreen(detail);
}

function DetailAction({ label, ariaLabel, disabled, onClick, children }: {
    label: string;
    ariaLabel: string;
    disabled: boolean;
    onClick: () => void;
    children: ReactNode;
}) {
    return (
        <button
            type="button"
            aria-label={ariaLabel}
            disabled={disabled}
            onClick={onClick}
            className={`flex min-w-0 flex-1 flex-col items-center gap-2 rounded-[12px] py-4 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ios-blue ${
                disabled
                    ? 'bg-surface/55 text-ios-gray'
                    : 'bg-surface text-ios-blue active:opacity-65'
            }`}
        >
            {children}
            <span className="max-w-full truncate px-1 text-[13px] font-medium">{label}</span>
        </button>
    );
}
