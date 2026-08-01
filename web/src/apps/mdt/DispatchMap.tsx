import { useMemo, useRef } from 'react';
import { Crosshair, Map as MapIcon } from 'lucide-react';

import { t } from '@/i18n';
import { EmptyState } from '@/ui/EmptyState';
import { MapView, usePinStyle, type MapViewHandle } from '@/apps/maps/MapView';

import { unitCodeLabel } from './UnitsColumn';

import type { Call, MapPoint, Unit } from './data';

const CALL_TINT: Record<number, string> = {
    1: '#FF3B30',
    2: '#FF9500',
    3: '#0A84FF',
    4: '#8E8E93',
};

const CODE_TINT: Record<string, string> = {
    '10-8':  '#34C759',
    '10-6':  '#FF9500',
    '10-7':  '#FF3B30',
    '10-90': '#0A84FF',
};

function CallPin({ call, selected, onPress }: {
    call:     Call;
    selected: boolean;
    onPress:  () => void;
}) {
    const style = usePinStyle(call.coords!.x, call.coords!.y);
    const tint = CALL_TINT[call.priority] ?? CALL_TINT[4];

    return (
        <button
            type="button"
            onClick={onPress}
            style={{ ...style, zIndex: selected ? 30 : 20 }}
            className="flex flex-col items-center"
            aria-label={`${call.code} ${call.location}`}
        >
            <span
                className={`flex items-center gap-1 rounded-full px-2 py-[3px] text-[11px] font-bold uppercase tracking-wide text-white shadow-[0_1px_4px_rgba(0,0,0,0.35)] ring-1 ring-black/10 transition-transform duration-150 ${
                    selected ? 'scale-110' : ''
                }`}
                style={{ backgroundColor: tint }}
            >
                {call.code}
            </span>
            <span
                className="mt-[-1px] h-[9px] w-[2px] rounded-full"
                style={{ backgroundColor: tint }}
            />
            {selected && (
                <span
                    className="absolute -z-10 h-[42px] w-[42px] rounded-full opacity-30"
                    style={{ backgroundColor: tint }}
                />
            )}
        </button>
    );
}

function UnitPin({ unit, selected, onPress }: {
    unit:     Unit;
    selected: boolean;
    onPress:  () => void;
}) {
    const style = usePinStyle(unit.coords!.x, unit.coords!.y);
    const tint = CODE_TINT[unit.code] ?? CODE_TINT['10-8'];

    return (
        <button
            type="button"
            onClick={onPress}
            style={{ ...style, zIndex: selected ? 29 : 15 }}
            className="flex flex-col items-center"
            aria-label={`${unit.callsign} ${unitCodeLabel(unit.code)}`}
        >
            <span
                className={`h-[13px] w-[13px] rounded-full border-[2.5px] border-white shadow-[0_1px_3px_rgba(0,0,0,0.4)] transition-transform duration-150 ${
                    selected ? 'scale-125' : ''
                }`}
                style={{ backgroundColor: tint }}
            />
            <span className="mt-0.5 rounded-[5px] bg-black/65 px-1.5 py-[1px] text-[10px] font-bold tabular-nums tracking-wide text-white">
                {unit.callsign || '--'}
            </span>
        </button>
    );
}

export function DispatchMap({ calls, units, selectedCall, selectedUnit, onSelectCall, onSelectUnit }: {
    calls:         Call[];
    units:         Unit[];
    selectedCall?: string | null;
    selectedUnit?: string | null;
    onSelectCall:  (id: string) => void;
    onSelectUnit:  (citizenid: string) => void;
}) {
    const mapRef = useRef<MapViewHandle>(null);

    const plottedCalls = useMemo(() => calls.filter(c => c.coords), [calls]);
    const plottedUnits = useMemo(() => units.filter(u => u.coords), [units]);

    const points = useMemo<MapPoint[]>(
        () => [...plottedCalls, ...plottedUnits].map(p => p.coords!),
        [plottedCalls, plottedUnits],
    );

    const focus = useMemo(() => {
        const call = selectedCall ? plottedCalls.find(c => c.id === selectedCall) : undefined;
        if (call) return call.coords;
        const unit = selectedUnit ? plottedUnits.find(u => u.citizenid === selectedUnit) : undefined;
        return unit?.coords;
    }, [selectedCall, selectedUnit, plottedCalls, plottedUnits]);

    const framed = useRef<MapPoint[] | null>(null);
    if (!framed.current && points.length > 0) framed.current = points;
    const initialFrame = framed.current;

    if (points.length === 0) {
        return (
            <div className="flex min-h-0 flex-1 items-center justify-center px-10">
                <EmptyState
                    center
                    icon={MapIcon}
                    title={t('mdt.mapEmpty', 'Nothing to plot')}
                    subtitle={t('mdt.mapEmptySub', 'Calls and units appear here as soon as one is on the board with a location.')}
                />
            </div>
        );
    }

    return (
        <div className="relative min-h-0 flex-1 overflow-hidden">
            <MapView ref={mapRef} fitTo={initialFrame ?? undefined} centerTo={focus ?? undefined}>
                {plottedUnits.map(u => (
                    <UnitPin
                        key={u.citizenid}
                        unit={u}
                        selected={u.citizenid === selectedUnit}
                        onPress={() => onSelectUnit(u.citizenid)}
                    />
                ))}
                {plottedCalls.map(c => (
                    <CallPin
                        key={c.id}
                        call={c}
                        selected={c.id === selectedCall}
                        onPress={() => onSelectCall(c.id)}
                    />
                ))}
            </MapView>

            <button
                type="button"
                onClick={() => mapRef.current?.fitWorld(points, 0.22)}
                aria-label={t('mdt.mapFit', 'Frame everything')}
                className="absolute left-3 top-3 z-40 flex h-[34px] w-[34px] items-center justify-center rounded-full bg-[#efefef] text-ios-gray shadow-[0_1px_4px_rgba(0,0,0,0.18)] ring-1 ring-black/[0.06] transition-colors duration-150 hover:bg-[#f6f6f6] hover:text-black active:bg-[#e2e2e4] dark:bg-elevated dark:ring-white/[0.08] dark:hover:text-white"
            >
                <Crosshair className="h-[17px] w-[17px]" strokeWidth={2.2} />
            </button>

            <div className="pointer-events-none absolute bottom-3 left-3 right-3 z-40 flex items-center justify-between gap-3">
                <div className="flex items-center gap-3 rounded-[10px] bg-black/60 px-3 py-[7px] backdrop-blur-[2px]">
                    {(['10-8', '10-90', '10-6', '10-7'] as const).map(code => (
                        <span key={code} className="flex items-center gap-[5px]">
                            <span
                                className="h-[8px] w-[8px] shrink-0 rounded-full ring-1 ring-white/70"
                                style={{ backgroundColor: CODE_TINT[code] }}
                            />
                            <span className="text-[10.5px] font-semibold tabular-nums tracking-wide text-white/85">
                                {code}
                            </span>
                        </span>
                    ))}
                </div>
                <div className="rounded-[10px] bg-black/60 px-3 py-[7px] text-[10.5px] font-semibold tabular-nums tracking-wide text-white/75 backdrop-blur-[2px]">
                    {t('mdt.mapCounts', '{c} calls · {u} units', { c: plottedCalls.length, u: plottedUnits.length })}
                </div>
            </div>
        </div>
    );
}
