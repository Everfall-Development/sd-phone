import { BriefcaseBusiness, MapPin } from 'lucide-react';

import type { WidgetSize, WidgetTheme } from '@/apps/appstore/appsApi';
import type { InboxThread } from '@/apps/services/servicesApi';
import { ServiceAvatar } from '@/apps/services/ServiceAvatar';
import { t } from '@/i18n';
import { requestOpenMaps } from '@/shell/deeplink';
import { useWidgetData } from '@/stores/widgetDataStore';
import { nearbyOpenBusinesses, prioritizedBusinessThreads, type NearbyBusiness } from './businessesWidgetData';
import { WidgetTile, palette } from './WidgetTile';
import type { Palette } from './WidgetTile';

function distanceLabel(distance: number | null): string {
    if (distance === null) return '';
    if (distance < 1000) return `${Math.max(1, Math.round(distance))} m`;
    return `${(distance / 1000).toFixed(distance < 10_000 ? 1 : 0)} km`;
}

function Header({ p, label }: { p: Palette; label: string }) {
    return (
        <div className="flex min-w-0 shrink-0 items-center gap-1.5">
            <BriefcaseBusiness className="h-[13px] w-[13px] shrink-0" strokeWidth={2.4} style={{ color: p.sub }} />
            <span className="truncate text-[11px] font-semibold" style={{ color: p.sub }}>
                {label}
            </span>
        </div>
    );
}

function openBusinessThread(thread: InboxThread): void {
    window.postMessage(
        {
            action: 'sd-phone:launchApp',
            data: {
                id: 'services',
                link: {
                    services: {
                        route: 'inbox',
                        entityType: 'thread',
                        entityId: thread.key,
                        scope: 'job',
                        thread: thread.key,
                    },
                },
            },
        },
        '*',
    );
}

function openBusiness(company: NearbyBusiness): void {
    window.postMessage(
        {
            action: 'sd-phone:launchApp',
            data: {
                id: 'services',
                link: {
                    services: {
                        route: 'directory',
                        entityType: 'business',
                        entityId: company.id,
                    },
                },
            },
        },
        '*',
    );
}

function openBusinessMap(company: NearbyBusiness): void {
    if (!company.coords) return;
    requestOpenMaps({
        label: company.name,
        x: company.coords.x,
        y: company.coords.y,
        color: company.color,
        companyId: company.id,
    });
}

function InboxSummary({ threads, p, size }: { threads: InboxThread[]; p: Palette; size: WidgetSize }) {
    const unread = threads.reduce((total, thread) => total + thread.unread, 0);
    const rows = threads.slice(0, size === 'sm' ? 1 : 3);

    return (
        <div className="flex min-h-0 flex-1 flex-col">
            <div className="mt-1.5 flex items-baseline gap-1.5">
                <span className="text-[25px] font-semibold leading-none tabular-nums" style={{ color: p.fg }}>
                    {unread}
                </span>
                <span className="text-[12px]" style={{ color: p.sub }}>
                    {t('widgets.businessUnread', 'unread')}
                </span>
            </div>
            <div className="mt-auto min-h-0">
                {rows.length === 0 ? (
                    <div className="text-[12px]" style={{ color: p.faint }}>
                        {t('widgets.businessInboxClear', 'Inbox clear')}
                    </div>
                ) : (
                    rows.map((thread, index) => (
                        <button
                            type="button"
                            key={thread.key}
                            aria-label={t('widgets.openBusinessThread', 'Open conversation with {name}', {
                                name: thread.name,
                            })}
                            onPointerDown={(event) => event.stopPropagation()}
                            onClick={(event) => {
                                event.stopPropagation();
                                openBusinessThread(thread);
                            }}
                            className="flex min-w-0 w-full items-center gap-2 py-1 text-left active:opacity-60 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ios-blue"
                            style={index > 0 ? { borderTop: `1px solid ${p.rule}` } : undefined}
                        >
                            <span className="min-w-0 flex-1 truncate text-[12px] font-medium" style={{ color: p.fg }}>
                                {thread.name}
                            </span>
                            {thread.unread > 0 && (
                                <span
                                    className="shrink-0 text-[11px] font-semibold tabular-nums"
                                    style={{ color: p.sub }}
                                >
                                    {thread.unread}
                                </span>
                            )}
                        </button>
                    ))
                )}
            </div>
        </div>
    );
}

function NearbySummary({ companies, p, size }: { companies: NearbyBusiness[]; p: Palette; size: WidgetSize }) {
    const rows = companies.slice(0, size === 'sm' ? 1 : 3);

    if (rows.length === 0) {
        return (
            <div className="flex min-h-0 flex-1 items-center">
                <span className="text-[13px] leading-snug" style={{ color: p.sub }}>
                    {t('widgets.noOpenBusinesses', 'No businesses open')}
                </span>
            </div>
        );
    }

    return (
        <div className="mt-auto min-h-0">
            {rows.map((company, index) => (
                <div
                    key={company.id}
                    className="flex min-w-0 items-center gap-2 py-1.5"
                    style={index > 0 ? { borderTop: `1px solid ${p.rule}` } : undefined}
                >
                    <button
                        type="button"
                        aria-label={t('widgets.openBusiness', 'Open {name}', { name: company.name })}
                        onPointerDown={(event) => event.stopPropagation()}
                        onClick={(event) => {
                            event.stopPropagation();
                            openBusiness(company);
                        }}
                        className="flex min-w-0 flex-1 items-center gap-2 text-left active:opacity-60 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ios-blue"
                    >
                        <ServiceAvatar emoji={company.emoji} iconUrl={company.iconUrl} size={18} />
                        <div className="min-w-0 flex-1">
                            <div className="truncate text-[12px] font-semibold" style={{ color: p.fg }}>
                                {company.name}
                            </div>
                            {size !== 'sm' && (
                                <div className="truncate text-[10px]" style={{ color: p.faint }}>
                                    {company.category}
                                </div>
                            )}
                        </div>
                        <span className="shrink-0 text-[10px] tabular-nums" style={{ color: p.sub }}>
                            {distanceLabel(company.distance)}
                        </span>
                    </button>
                    {company.coords && (
                        <button
                            type="button"
                            aria-label={t('widgets.openBusinessMap', 'Open {name} in Maps', {
                                name: company.name,
                            })}
                            onPointerDown={(event) => event.stopPropagation()}
                            onClick={(event) => {
                                event.stopPropagation();
                                openBusinessMap(company);
                            }}
                            className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full active:opacity-60 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ios-blue"
                            style={{ color: p.sub }}
                        >
                            <MapPin className="h-[14px] w-[14px]" strokeWidth={2.4} />
                        </button>
                    )}
                </div>
            ))}
        </div>
    );
}

export function BusinessesWidget({
    size,
    width,
    height,
    theme = 'dark',
}: {
    size: WidgetSize;
    width: number;
    height: number;
    theme?: WidgetTheme;
}) {
    const companies = useWidgetData((state) => state.businesses);
    const inbox = useWidgetData((state) => state.businessInbox);
    const here = useWidgetData((state) => state.businessHere);
    const unavailable = useWidgetData((state) => state.businessUnavailable);
    const p = palette(theme);
    const threads = prioritizedBusinessThreads(inbox);
    const staffView = inbox?.hasJob === true;

    return (
        <WidgetTile
            width={width}
            height={height}
            radius={size === 'sm' ? 22 : 26}
            tint={p.bg}
            glass={theme === 'glass'}
            hairline={false}
        >
            <div className="flex h-full w-full flex-col p-3.5">
                <Header
                    p={p}
                    label={
                        staffView ? t('widgets.businessInbox', 'Business Inbox') : t('widgets.businesses', 'Businesses')
                    }
                />
                {unavailable ? (
                    <div className="flex min-h-0 flex-1 items-center">
                        <span className="text-[13px]" style={{ color: p.sub }}>
                            {t('widgets.businessesUnavailable', 'Unavailable')}
                        </span>
                    </div>
                ) : staffView ? (
                    <InboxSummary threads={threads} p={p} size={size} />
                ) : (
                    <NearbySummary companies={nearbyOpenBusinesses(companies, here)} p={p} size={size} />
                )}
            </div>
        </WidgetTile>
    );
}
