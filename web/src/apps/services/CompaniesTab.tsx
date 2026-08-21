import { useLayoutEffect, useMemo, useRef, useState } from 'react';
import { Building2, ChevronRight, RotateCcw, Search, SlidersHorizontal } from 'lucide-react';

import { fetchNui, isFiveM } from '@/core/nui';
import { t } from '@/i18n';
import { requestOpenMaps, type BusinessesCompanyTarget } from '@/shell/deeplink';
import { ActionSheet } from '@/ui/ActionSheet';
import { AlertDialog } from '@/ui/AlertDialog';
import { EmptyState } from '@/ui/EmptyState';
import { PromptDialog } from '@/ui/PromptDialog';
import { SearchBar } from '@/ui/SearchBar';
import { SegmentedControl } from '@/ui/SegmentedControl';
import { portalToPhoneScreen } from '@/ui/portal';
import { BusinessDetail } from './BusinessDetail';
import { ServiceAvatar } from './ServiceAvatar';
import { callCompany, messageCompany, type Inbox } from './servicesApi';
import { filterBusinesses, type BusinessAvailability, type Company } from './data';

const ALL_CATEGORIES = 'All';

type PendingAction = {
    companyId: string;
    action: 'call' | 'message';
};

function openCompanyInMaps(company: Company) {
    if (!company.coords) return;
    requestOpenMaps({
        label: company.name,
        x: company.coords.x,
        y: company.coords.y,
        color: company.color,
        companyId: company.id,
    });
}

export function CompaniesTab({
    companies,
    loaded,
    loading,
    unavailable,
    onRetry,
    onMessaged,
    target,
    targetNonce,
    onTargetDismiss,
}: {
    companies: Company[];
    loaded: boolean;
    loading: boolean;
    unavailable?: string;
    onRetry: () => void;
    onMessaged: (inbox: Inbox) => void;
    target: BusinessesCompanyTarget | null;
    targetNonce: number;
    onTargetDismiss: () => void;
}) {
    const [query, setQuery] = useState('');
    const [category, setCategory] = useState(ALL_CATEGORIES);
    const [availability, setAvailability] = useState<BusinessAvailability>('all');
    const [selectedId, setSelectedId] = useState<string | null>(null);
    const [categorySheet, setCategorySheet] = useState(false);
    const [messageTarget, setMessageTarget] = useState<Company | null>(null);
    const [locationTarget, setLocationTarget] = useState<Company | null>(null);
    const [pending, setPending] = useState<PendingAction | null>(null);
    const [error, setError] = useState<string | null>(null);
    const handledTargetNonce = useRef(0);

    const categories = useMemo(
        () => [ALL_CATEGORIES, ...Array.from(new Set(companies.map((company) => company.category))).sort()],
        [companies],
    );

    const visibleCompanies = useMemo(
        () => filterBusinesses(companies, query, category, availability),
        [availability, category, companies, query],
    );
    const selected = companies.find((company) => company.id === selectedId) ?? null;
    const hasFilters = query.trim() !== '' || category !== ALL_CATEGORIES || availability !== 'all';

    useLayoutEffect(() => {
        if (!target || !loaded || loading || handledTargetNonce.current === targetNonce) return;
        handledTargetNonce.current = targetNonce;

        const company = companies.find((candidate) => candidate.id === target.entityId);
        if (!company || unavailable) {
            onTargetDismiss();
            return;
        }

        setSelectedId(company.id);
    }, [companies, loaded, loading, onTargetDismiss, target, targetNonce, unavailable]);

    function locate(company: Company) {
        if (!company.coords) {
            setError(t('services.noLocationSet', 'No location is available for this business.'));
            return;
        }
        setLocationTarget(company);
    }

    async function setWaypoint(company: Company) {
        if (!company.coords || !isFiveM) return;
        try {
            const result = await fetchNui<{ success?: boolean; message?: string }>('sd-phone:maps:waypoint', {
                x: company.coords.x,
                y: company.coords.y,
            });
            if (result?.success !== false) return;
            setError(result.message ?? t('services.couldntLocate', "Couldn't set the waypoint."));
        } catch {
            setError(t('services.couldntLocate', "Couldn't set the waypoint."));
        }
    }

    function openInMaps(company: Company) {
        setSelectedId(null);
        onTargetDismiss();
        openCompanyInMaps(company);
    }

    async function call(company: Company) {
        if (pending) return;
        setPending({ companyId: company.id, action: 'call' });
        try {
            const result = await callCompany(company.id);
            if (result.success) return;
            setError(result.message ?? t('services.couldntCall', "Couldn't place the call."));
        } catch {
            setError(t('services.couldntCall', "Couldn't place the call."));
        } finally {
            setPending(null);
        }
    }

    async function sendMessage(body: string): Promise<string | void> {
        if (!messageTarget || pending) return t('services.pleaseWait', 'Please wait a moment.');
        const company = messageTarget;
        const text = body.trim();
        if (!text) return t('services.emptyMessage', 'Enter a message.');

        setPending({ companyId: company.id, action: 'message' });
        try {
            const result = await messageCompany(company.id, { kind: 'text', body: text });
            if (!result.success || !result.data?.inbox) {
                return result.message ?? t('services.couldntSend', "Couldn't send your message.");
            }
            onMessaged(result.data.inbox);
        } catch {
            return t('services.couldntSend', "Couldn't send your message.");
        } finally {
            setPending(null);
        }
    }

    function resetFilters() {
        setQuery('');
        setCategory(ALL_CATEGORIES);
        setAvailability('all');
    }

    const selectedPending = selected && pending?.companyId === selected.id ? pending.action : null;
    const categoryLabel = category === ALL_CATEGORIES ? t('services.categories', 'Categories') : category;

    return (
        <div className="flex min-h-0 flex-1 flex-col">
            <h1 className="px-5 pb-2 pt-1 text-[34px] font-bold tracking-tight text-black dark:text-white">
                {t('services.businesses', 'Businesses')}
            </h1>

            <SearchBar
                value={query}
                onChange={setQuery}
                placeholder={t('services.searchBusinesses', 'Search businesses')}
                className="mx-4 mb-3"
            />

            <div className="flex shrink-0 items-center gap-2 px-4 pb-3">
                <SegmentedControl
                    value={availability}
                    onChange={setAvailability}
                    options={[
                        { value: 'all', label: t('services.all', 'All') },
                        { value: 'open', label: t('services.openNow', 'Open') },
                    ]}
                    className="min-w-0 flex-1"
                />
                {categories.length > 2 && (
                    <button
                        type="button"
                        aria-label={t('services.filterCategory', 'Filter by category')}
                        aria-pressed={category !== ALL_CATEGORIES}
                        onClick={() => setCategorySheet(true)}
                        className={`flex h-[38px] max-w-[156px] shrink-0 items-center gap-2 rounded-[9px] px-3 text-[15px] font-medium active:opacity-65 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ios-blue ${
                            category === ALL_CATEGORIES
                                ? 'bg-black/[0.06] text-black/75 dark:bg-white/[0.12] dark:text-white/75'
                                : 'bg-ios-blue text-white'
                        }`}
                    >
                        <SlidersHorizontal className="h-[17px] w-[17px] shrink-0" strokeWidth={2.3} />
                        <span className="truncate">{categoryLabel}</span>
                    </button>
                )}
            </div>

            <div className="min-h-0 flex-1 overflow-y-auto no-scrollbar px-4 pb-6">
                {!loaded ? (
                    <DirectoryLoading />
                ) : unavailable ? (
                    <EmptyState
                        icon={Building2}
                        title={t('services.unavailableTitle', 'Businesses Unavailable')}
                        subtitle={unavailable}
                        action={
                            <button
                                type="button"
                                onClick={onRetry}
                                disabled={loading}
                                aria-busy={loading}
                                className="inline-flex items-center gap-2 rounded-[12px] bg-ios-blue px-5 py-3 text-[15px] font-semibold text-white active:opacity-70 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ios-blue focus-visible:ring-offset-2"
                            >
                                <RotateCcw className="h-4 w-4" />
                                {loading ? t('services.retrying', 'Retrying…') : t('services.tryAgain', 'Try Again')}
                            </button>
                        }
                    />
                ) : visibleCompanies.length === 0 ? (
                    <EmptyState
                        icon={hasFilters ? Search : Building2}
                        title={
                            hasFilters
                                ? t('services.noMatches', 'No Matches')
                                : t('services.noBusinesses', 'No Businesses')
                        }
                        circle={!hasFilters}
                        action={
                            hasFilters ? (
                                <button
                                    type="button"
                                    onClick={resetFilters}
                                    className="text-[16px] font-semibold text-ios-blue active:opacity-65 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ios-blue focus-visible:ring-offset-2"
                                >
                                    {t('services.clearFilters', 'Clear Filters')}
                                </button>
                            ) : undefined
                        }
                    />
                ) : (
                    <div className="overflow-hidden rounded-[14px] bg-surface">
                        {visibleCompanies.map((company, index) => (
                            <div key={company.id}>
                                {index > 0 && <div className="ml-[78px] h-px bg-black/[0.08] dark:bg-white/[0.09]" />}
                                <CompanyRow company={company} onOpen={() => setSelectedId(company.id)} />
                            </div>
                        ))}
                    </div>
                )}
            </div>

            {selected && (
                <BusinessDetail
                    company={selected}
                    pending={selectedPending}
                    onBack={() => {
                        setSelectedId(null);
                        onTargetDismiss();
                    }}
                    onCall={() => void call(selected)}
                    onMessage={() => setMessageTarget(selected)}
                    onLocate={() => locate(selected)}
                />
            )}

            {messageTarget &&
                portalToPhoneScreen(
                    <PromptDialog
                        title={t('services.messageName', 'Message {name}', { name: messageTarget.name })}
                        placeholder={t('services.typeAMessage', 'Type a message…')}
                        confirmLabel={t('services.send', 'Send')}
                        maxLength={300}
                        onCancel={() => setMessageTarget(null)}
                        onConfirm={sendMessage}
                    />,
                )}

            {categorySheet && (
                <ActionSheet
                    actions={categories.map((option) => ({
                        label: option === ALL_CATEGORIES ? t('services.allCategories', 'All Categories') : option,
                        onClick: () => setCategory(option),
                    }))}
                    cancelLabel={t('services.cancel', 'Cancel')}
                    onClose={() => setCategorySheet(false)}
                />
            )}

            {locationTarget && (
                <ActionSheet
                    actions={[
                        ...(isFiveM
                            ? [
                                  {
                                      label: t('services.setWaypoint', 'Set Waypoint'),
                                      onClick: () => void setWaypoint(locationTarget),
                                  },
                              ]
                            : []),
                        {
                            label: t('services.openInMaps', 'Open in Maps'),
                            onClick: () => openInMaps(locationTarget),
                        },
                    ]}
                    cancelLabel={t('services.cancel', 'Cancel')}
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

function CompanyRow({ company, onOpen }: { company: Company; onOpen: () => void }) {
    const open = company.status === 'open';
    return (
        <button
            type="button"
            onClick={onOpen}
            aria-label={`${company.name}, ${company.status === 'open' ? t('services.open', 'Open') : t('services.closed', 'Closed')}, ${company.category}`}
            className="flex min-h-[88px] w-full items-center gap-3 px-3 py-3 text-left active:bg-black/[0.05] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ios-blue dark:active:bg-white/[0.06]"
        >
            <ServiceAvatar emoji={company.emoji} iconUrl={company.iconUrl} size={54} />

            <div className="min-w-0 flex-1">
                <div className="truncate text-[18px] font-semibold text-black dark:text-white">{company.name}</div>
                <div className="mt-0.5 truncate text-[14px] font-medium text-black/50 dark:text-white/50">
                    {company.location}
                </div>
                <div className="mt-1 flex items-center gap-1.5 text-[13px] font-semibold">
                    <span className={`h-2 w-2 rounded-full ${open ? 'bg-ios-green' : 'bg-ios-gray'}`} aria-hidden />
                    <span className={open ? 'text-[#248A3D] dark:text-[#30D158]' : 'text-ios-gray'}>
                        {open ? t('services.open', 'Open') : t('services.closed', 'Closed')}
                    </span>
                    <span className="font-medium text-black/35 dark:text-white/35" aria-hidden>
                        ·
                    </span>
                    <span className="truncate font-medium text-black/45 dark:text-white/45">{company.category}</span>
                </div>
            </div>

            <ChevronRight className="h-5 w-5 shrink-0 text-black/20 dark:text-white/25" strokeWidth={2.4} />
        </button>
    );
}

function DirectoryLoading() {
    return (
        <div
            role="status"
            aria-label={t('services.loadingBusinesses', 'Loading businesses')}
            aria-busy="true"
            className="overflow-hidden rounded-[14px] bg-surface"
        >
            {[0, 1, 2, 3].map((index) => (
                <div key={index}>
                    {index > 0 && <div className="ml-[78px] h-px bg-black/[0.06] dark:bg-white/[0.07]" />}
                    <div className="flex min-h-[88px] items-center gap-3 px-3 py-3">
                        <div className="h-[54px] w-[54px] shrink-0 rounded-full bg-black/[0.07] dark:bg-white/[0.08]" />
                        <div className="min-w-0 flex-1">
                            <div className="h-4 w-3/5 rounded bg-black/[0.08] dark:bg-white/[0.09]" />
                            <div className="mt-2 h-3 w-2/5 rounded bg-black/[0.06] dark:bg-white/[0.07]" />
                            <div className="mt-2 h-3 w-1/3 rounded bg-black/[0.06] dark:bg-white/[0.07]" />
                        </div>
                    </div>
                </div>
            ))}
        </div>
    );
}
