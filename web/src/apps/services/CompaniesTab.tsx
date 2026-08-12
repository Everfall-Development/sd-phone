import { useMemo, useState, type ReactNode } from 'react';
import { Building2, MessageSquare, Navigation, Phone, RotateCcw } from 'lucide-react';

import { device } from '@device';
import { fetchNui, isFiveM } from '@/core/nui';
import { t } from '@/i18n';
import { requestOpenMaps } from '@/shell/deeplink';
import { ActionSheet } from '@/ui/ActionSheet';
import { AlertDialog } from '@/ui/AlertDialog';
import { EmptyState } from '@/ui/EmptyState';
import { PromptDialog } from '@/ui/PromptDialog';
import { SearchBar } from '@/ui/SearchBar';
import { ServiceAvatar } from './ServiceAvatar';
import { callCompany, messageCompany, type Inbox } from './servicesApi';
import { filterBusinesses, type Company } from './data';

const ALL_CATEGORIES = 'All';

export function CompaniesTab({ companies, loaded, unavailable, onRetry, onMessaged }: {
    companies: Company[];
    loaded: boolean;
    unavailable?: string;
    onRetry: () => void;
    onMessaged: (inbox: Inbox) => void;
}) {
    const [query, setQuery] = useState('');
    const [category, setCategory] = useState(ALL_CATEGORIES);
    const [messageTarget, setMessageTarget] = useState<Company | null>(null);
    const [locationTarget, setLocationTarget] = useState<Company | null>(null);
    const [error, setError] = useState<string | null>(null);

    const categories = useMemo(() => [
        ALL_CATEGORIES,
        ...Array.from(new Set(companies.map(company => company.category))).sort(),
    ], [companies]);

    const visibleCompanies = useMemo(
        () => filterBusinesses(companies, query, category),
        [category, companies, query],
    );

    function locate(company: Company) {
        if (!company.coords) {
            setError(t('services.noLocationSet', 'No location is available for this business.'));
            return;
        }
        setLocationTarget(company);
    }

    function setWaypoint(company: Company) {
        if (!company.coords || !isFiveM) return;
        void fetchNui('sd-phone:maps:waypoint', { x: company.coords.x, y: company.coords.y });
    }

    function openInMaps(company: Company) {
        if (!company.coords) return;
        requestOpenMaps({
            label: company.name,
            x: company.coords.x,
            y: company.coords.y,
            color: company.color,
            companyId: company.id,
        });
    }

    async function call(company: Company) {
        const result = await callCompany(company.id);
        if (!result.success) {
            setError(result.message ?? t('services.couldntCall', "Couldn't place the call."));
        }
    }

    function sendMessage(body: string) {
        if (!messageTarget) return;
        const company = messageTarget;
        const text = body.trim();
        setMessageTarget(null);
        if (!text) return;

        void messageCompany(company.id, { kind: 'text', body: text }).then(inbox => {
            if (inbox) {
                onMessaged(inbox);
                return;
            }
            setError(t('services.couldntSend', "Couldn't send your message."));
        });
    }

    return (
        <div className="flex min-h-0 flex-1 flex-col">
            <h1 className="px-5 pb-2 pt-1 text-[34px] font-bold tracking-tight text-black dark:text-white">
                {t('services.businesses', 'Businesses')}
            </h1>

            <SearchBar
                value={query}
                onChange={setQuery}
                placeholder={t('services.searchBusinesses', 'Search businesses')}
                className="mx-4 mb-2"
            />

            {categories.length > 2 && (
                <div className="flex shrink-0 gap-2 overflow-x-auto no-scrollbar px-4 pb-3">
                    {categories.map(option => (
                        <button
                            key={option}
                            type="button"
                            onClick={() => setCategory(option)}
                            className={`shrink-0 rounded-full px-3.5 py-1.5 text-[14px] font-semibold transition-colors ${
                                category === option
                                    ? 'bg-black text-white dark:bg-white dark:text-black'
                                    : 'bg-surface text-black/70 dark:text-white/75'
                            }`}
                        >
                            {option}
                        </button>
                    ))}
                </div>
            )}

            <div className="min-h-0 flex-1 overflow-y-auto no-scrollbar px-4 pb-6">
                {!loaded ? null : unavailable ? (
                    <EmptyState
                        icon={Building2}
                        title={t('services.unavailableTitle', 'Businesses Unavailable')}
                        subtitle={unavailable}
                        action={(
                            <button
                                type="button"
                                onClick={onRetry}
                                className="inline-flex items-center gap-2 rounded-full bg-ios-blue px-5 py-2.5 text-[15px] font-semibold text-white active:opacity-70"
                            >
                                <RotateCcw className="h-4 w-4" />
                                {t('services.tryAgain', 'Try Again')}
                            </button>
                        )}
                    />
                ) : visibleCompanies.length === 0 ? (
                    <EmptyState icon={Building2} title={t('services.noBusinesses', 'No Businesses Found')} />
                ) : (
                    <div className="overflow-hidden rounded-[14px] bg-surface">
                        {visibleCompanies.map((company, index) => (
                            <div key={company.id}>
                                {index > 0 && <div className="ml-[86px] h-px bg-black/10 dark:bg-white/10" />}
                                <CompanyRow
                                    company={company}
                                    onLocate={() => locate(company)}
                                    onCall={() => void call(company)}
                                    onMessage={() => setMessageTarget(company)}
                                />
                            </div>
                        ))}
                    </div>
                )}
            </div>

            {messageTarget && (
                <PromptDialog
                    title={t('services.messageName', 'Message {name}', { name: messageTarget.name })}
                    placeholder={t('services.typeAMessage', 'Type a message…')}
                    confirmLabel={t('services.send', 'Send')}
                    maxLength={300}
                    onCancel={() => setMessageTarget(null)}
                    onConfirm={sendMessage}
                />
            )}

            {locationTarget && (
                <ActionSheet
                    actions={[
                        { label: t('services.setWaypoint', 'Set Waypoint'), onClick: () => setWaypoint(locationTarget) },
                        { label: t('services.openInMaps', 'Open in Maps'), onClick: () => openInMaps(locationTarget) },
                    ]}
                    onClose={() => setLocationTarget(null)}
                />
            )}

            {error && (
                <AlertDialog
                    title={t('services.couldntComplete', "Couldn't Complete")}
                    message={error}
                    confirmLabel={t('services.ok', 'OK')}
                    hideCancel
                    onCancel={() => setError(null)}
                    onConfirm={() => setError(null)}
                />
            )}
        </div>
    );
}

function CompanyRow({ company, onLocate, onCall, onMessage }: {
    company: Company;
    onLocate: () => void;
    onCall: () => void;
    onMessage: () => void;
}) {
    return (
        <div className="flex min-h-[86px] items-center gap-3 px-3 py-3.5">
            <ServiceAvatar color={company.color} emoji={company.emoji} iconUrl={company.iconUrl} size={58} />

            <div className="min-w-0 flex-1">
                <div className="truncate text-[18px] font-semibold text-black dark:text-white">{company.name}</div>
                <div className="mt-0.5 truncate text-[14px] font-medium text-ios-gray">{company.category}</div>
                <div className={`mt-1 text-[13px] font-semibold ${company.status === 'open' ? 'text-[#248A3D] dark:text-[#30D158]' : 'text-ios-gray'}`}>
                    {company.status === 'open' ? t('services.open', 'Open') : t('services.closed', 'Closed')}
                </div>
            </div>

            <div className="flex shrink-0 items-center gap-1.5">
                {company.coords && (
                    <ActionButton label={t('services.locateName', 'Locate {name}', { name: company.name })} onClick={onLocate}>
                        <Navigation className="h-[19px] w-[19px]" strokeWidth={2.3} />
                    </ActionButton>
                )}
                {company.canCall && device.calls && (
                    <ActionButton label={t('services.callName', 'Call {name}', { name: company.name })} onClick={onCall}>
                        <Phone className="h-[19px] w-[19px]" strokeWidth={2.3} />
                    </ActionButton>
                )}
                {company.canMessage && (
                    <ActionButton label={t('services.messageName', 'Message {name}', { name: company.name })} onClick={onMessage}>
                        <MessageSquare className="h-[19px] w-[19px]" strokeWidth={2.3} />
                    </ActionButton>
                )}
            </div>
        </div>
    );
}

function ActionButton({ label, onClick, children }: { label: string; onClick: () => void; children: ReactNode }) {
    return (
        <button
            type="button"
            aria-label={label}
            onClick={onClick}
            className="flex h-[40px] w-[40px] items-center justify-center rounded-full bg-black/[0.06] text-ios-blue active:bg-black/10 dark:bg-white/10 dark:active:bg-white/15"
        >
            {children}
        </button>
    );
}
