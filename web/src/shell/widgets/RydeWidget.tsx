import { CarFront } from 'lucide-react';

import type { WidgetSize, WidgetTheme } from '@/apps/appstore/appsApi';
import type { RydeActiveRide, RydeSync } from '@/apps/ryde/rydeApi';
import { t } from '@/i18n';
import { formatMoney } from '@/lib/money';
import { useWidgetData } from '@/stores/widgetDataStore';
import { WidgetTile, palette } from './WidgetTile';

export interface ActiveRydeWidgetRide {
    role: 'rider' | 'driver';
    ride: RydeActiveRide;
}

function isActiveRide(ride: RydeActiveRide | null | undefined): ride is RydeActiveRide {
    return !!ride && ride.status !== 'completed' && ride.status !== 'cancelled' && ride.status !== 'declined';
}

export function activeRydeWidgetRide(sync: RydeSync | null): ActiveRydeWidgetRide | null {
    if (isActiveRide(sync?.rider)) return { role: 'rider', ride: sync.rider };
    if (isActiveRide(sync?.driver)) return { role: 'driver', ride: sync.driver };
    return null;
}

export function rydeStatusLabel(status: string, role: 'rider' | 'driver'): string {
    if (status === 'finding') return role === 'driver' ? 'Ride request' : 'Finding a driver';
    if (status === 'offered') return role === 'driver' ? 'Offer sent' : 'Driver found';
    if (status === 'enroute_pickup') return role === 'driver' ? 'Heading to pickup' : 'Driver on the way';
    if (status === 'arriving') return 'Arriving';
    if (status === 'in_progress') return 'On the way';
    return 'No active ride';
}

function locationLabel(location: { label: string }): string {
    return location.label || t('widgets.rydeLocation', 'Location');
}

export function RydeWidget({ size, width, height, theme = 'dark' }: {
    size: WidgetSize;
    width: number;
    height: number;
    theme?: WidgetTheme;
}) {
    const sync = useWidgetData(state => state.ryde);
    const active = activeRydeWidgetRide(sync);
    const p = palette(theme);
    const waiting = sync?.requests?.length ?? 0;

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
                <div className="flex min-w-0 shrink-0 items-center gap-1.5">
                    <CarFront className="h-[13px] w-[13px] shrink-0" strokeWidth={2.4} style={{ color: p.sub }} />
                    <span className="truncate text-[11px] font-semibold" style={{ color: p.sub }}>{t('widgets.ryde', 'Ryde')}</span>
                </div>

                {!active ? (
                    <div className="flex min-h-0 flex-1 flex-col justify-center">
                        <div className="text-[16px] font-semibold leading-tight" style={{ color: p.fg }}>
                            {sync?.driverAllowed && sync.duty
                                ? t('widgets.rydeReady', 'Ready to drive')
                                : t('widgets.rydeIdle', 'No active ride')}
                        </div>
                        {sync?.driverAllowed && sync.duty && waiting > 0 && (
                            <div className="mt-1 text-[12px] tabular-nums" style={{ color: p.sub }}>
                                {waiting === 1 ? t('widgets.rydeOneRequest', '1 request') : `${waiting} ${t('widgets.rydeRequests', 'requests')}`}
                            </div>
                        )}
                    </div>
                ) : (
                    <div className="flex min-h-0 flex-1 flex-col">
                        <div className="mt-2 text-[17px] font-semibold leading-tight" style={{ color: p.fg }}>
                            {rydeStatusLabel(active.ride.status, active.role)}
                        </div>
                        <div className="mt-1 truncate text-[12px]" style={{ color: p.sub }}>
                            {locationLabel(active.ride.dropoff)}
                        </div>

                        {size !== 'sm' && (
                            <div className="mt-auto flex min-w-0 items-end gap-3 pt-2" style={{ borderTop: `1px solid ${p.rule}` }}>
                                <div className="min-w-0 flex-1">
                                    <div className="truncate text-[10px]" style={{ color: p.faint }}>{t('widgets.rydePickup', 'Pickup')}</div>
                                    <div className="truncate text-[12px] font-medium" style={{ color: p.fg }}>{locationLabel(active.ride.pickup)}</div>
                                </div>
                                {active.ride.fare !== undefined && (
                                    <div className="shrink-0 text-[13px] font-semibold tabular-nums" style={{ color: p.fg }}>
                                        {formatMoney(active.ride.fare, { whole: true })}
                                    </div>
                                )}
                            </div>
                        )}

                        {size === 'sm' && active.ride.fare !== undefined && (
                            <div className="mt-auto text-[13px] font-semibold tabular-nums" style={{ color: p.fg }}>
                                {formatMoney(active.ride.fare, { whole: true })}
                            </div>
                        )}
                    </div>
                )}
            </div>
        </WidgetTile>
    );
}
