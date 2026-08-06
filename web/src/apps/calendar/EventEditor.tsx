import { useState } from 'react';
import { Check, Trash2, X } from 'lucide-react';

import { useTheme } from '@/stores/themeStore';
import { TimeWheel } from '@/ui/TimeWheel';
import { Toggle } from '@/ui/Toggle';
import { EVENT_COLORS, formatLongDate, formatTime, newId } from './data';
import type { CalEvent } from './data';
import { t } from '@/i18n';

interface Props {
    dayKey: string;
    dayDate: Date;
    existing?: CalEvent;
    onSave: (event: CalEvent) => void;
    onDelete?: () => void;
    onClose: () => void;
}

export function EventEditor({ dayKey, dayDate, existing, onSave, onDelete, onClose }: Props) {
    const { theme } = useTheme('theme');
    const isDark = theme === 'dark';
    const [title, setTitle] = useState(existing?.title ?? '');
    const [location, setLocation] = useState(existing?.location ?? '');
    const [notes, setNotes] = useState(existing?.notes ?? '');
    const [allDay, setAllDay] = useState(existing?.allDay ?? false);
    const [start, setStart] = useState(existing?.start ?? '09:00');
    const [end, setEnd] = useState(existing?.end ?? '10:00');
    const [color, setColor] = useState(existing?.color ?? EVENT_COLORS[0]);
    const [activeTime, setActiveTime] = useState<'start' | 'end' | null>(null);

    const groupBackground = 'rgb(var(--surface))';
    const pageBackground = 'rgb(var(--base))';
    const divider = isDark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.1)';

    function commit(): void {
        const trimmed = title.trim();
        if (!trimmed) return;
        onSave({
            id: existing?.id ?? newId(),
            dayKey,
            title: trimmed,
            location: location.trim(),
            notes,
            allDay,
            start: allDay ? undefined : start,
            end: allDay ? undefined : end,
            color,
        });
    }

    function changeAllDay(value: boolean): void {
        setAllDay(value);
        if (value) setActiveTime(null);
    }

    function remove(): void {
        if (!onDelete) return;
        onDelete();
        onClose();
    }

    return (
        <div
            className="absolute inset-0 z-30 flex flex-col"
            style={{ background: pageBackground, color: isDark ? '#fff' : '#000' }}
        >
            <div className="shrink-0" style={{ height: 54 }} />

            <div className="relative flex h-11 shrink-0 items-center px-4">
                <button
                    type="button"
                    aria-label={t('calendar.cancel', 'Cancel')}
                    onClick={onClose}
                    className="flex items-center text-ios-red active:opacity-60"
                >
                    <X className="h-[22px] w-[22px]" strokeWidth={2.5} />
                </button>
                <div className="pointer-events-none absolute inset-x-0 flex justify-center">
                    <span className="text-[17px] font-semibold">
                        {existing ? t('calendar.editEvent', 'Edit Event') : t('calendar.newEventTitle', 'New Event')}
                    </span>
                </div>
                <button
                    type="button"
                    aria-label={t('calendar.saveEvent', 'Save event')}
                    onClick={commit}
                    disabled={!title.trim()}
                    className="ml-auto flex items-center text-ios-red active:opacity-60 disabled:opacity-30"
                >
                    <Check className="h-[22px] w-[22px]" strokeWidth={2.75} />
                </button>
            </div>

            <div className="flex-1 overflow-y-auto no-scrollbar pb-10">
                <div className="px-4 pb-2 pt-3 text-[22px] font-bold tracking-tight">
                    {formatLongDate(dayDate)}
                </div>

                <div className="mx-4 mt-2 overflow-hidden rounded-[10px]" style={{ background: groupBackground }}>
                    <input
                        type="text"
                        value={title}
                        onChange={event => setTitle(event.target.value)}
                        placeholder={t('calendar.title', 'Title')}
                        maxLength={100}
                        className="w-full bg-transparent px-4 py-3.5 text-[18px] outline-none placeholder:text-ios-gray"
                    />
                    <div style={{ height: 0.5, background: divider }} />
                    <input
                        type="text"
                        value={location}
                        onChange={event => setLocation(event.target.value)}
                        placeholder={t('calendar.location', 'Location')}
                        maxLength={160}
                        className="w-full bg-transparent px-4 py-3.5 text-[18px] outline-none placeholder:text-ios-gray"
                    />
                </div>

                <div className="mx-4 mt-6 overflow-hidden rounded-[10px]" style={{ background: groupBackground }}>
                    <div className="flex items-center px-4 py-3.5">
                        <span className="flex-1 text-[18px]">{t('calendar.allDay', 'All-day')}</span>
                        <Toggle on={allDay} onChange={changeAllDay} />
                    </div>
                    <div style={{ height: 0.5, background: divider }} />
                    <TimeRow
                        label={t('calendar.starts', 'Starts')}
                        value={start}
                        isDark={isDark}
                        disabled={allDay}
                        active={activeTime === 'start'}
                        onToggle={() => setActiveTime(current => current === 'start' ? null : 'start')}
                    />
                    <TimeWheel value={start} onChange={setStart} open={!allDay && activeTime === 'start'} />
                    <div style={{ height: 0.5, background: divider }} />
                    <TimeRow
                        label={t('calendar.ends', 'Ends')}
                        value={end}
                        isDark={isDark}
                        disabled={allDay}
                        active={activeTime === 'end'}
                        onToggle={() => setActiveTime(current => current === 'end' ? null : 'end')}
                    />
                    <TimeWheel value={end} onChange={setEnd} open={!allDay && activeTime === 'end'} />
                </div>

                <div className="mx-4 mt-6 overflow-hidden rounded-[10px]" style={{ background: groupBackground }}>
                    <div className="flex items-center px-4 py-3.5">
                        <span className="flex-1 text-[18px]">{t('calendar.color', 'Color')}</span>
                        <div className="flex items-center gap-[10px]">
                            {EVENT_COLORS.map(eventColor => (
                                <button
                                    key={eventColor}
                                    type="button"
                                    onClick={() => setColor(eventColor)}
                                    className="rounded-full active:scale-95"
                                    style={{
                                        width: 22,
                                        height: 22,
                                        background: eventColor,
                                        boxShadow: color === eventColor
                                            ? `0 0 0 2px ${groupBackground}, 0 0 0 4px ${eventColor}`
                                            : undefined,
                                        transition: 'transform 0.12s',
                                    }}
                                    aria-label={t('calendar.setColor', 'Set color {color}', { color: eventColor })}
                                />
                            ))}
                        </div>
                    </div>
                </div>

                <div className="mx-4 mt-6 overflow-hidden rounded-[10px]" style={{ background: groupBackground }}>
                    <textarea
                        value={notes}
                        onChange={event => setNotes(event.target.value)}
                        placeholder={t('calendar.notes', 'Notes')}
                        rows={6}
                        maxLength={2000}
                        className="w-full resize-none bg-transparent px-4 py-3.5 text-[19px] leading-relaxed outline-none placeholder:text-ios-gray"
                    />
                </div>

                {existing && onDelete ? (
                    <div className="mx-4 mt-6 overflow-hidden rounded-[10px]" style={{ background: groupBackground }}>
                        <button
                            type="button"
                            onClick={remove}
                            className="flex w-full items-center justify-center gap-2 px-4 py-3.5 text-ios-red active:bg-black/5 dark:active:bg-white/5"
                        >
                            <Trash2 className="h-[18px] w-[18px]" />
                            <span className="text-[18px]">{t('calendar.deleteEvent', 'Delete Event')}</span>
                        </button>
                    </div>
                ) : null}
            </div>
        </div>
    );
}

function TimeRow({ label, value, active, disabled, onToggle, isDark }: {
    label: string;
    value: string;
    active: boolean;
    disabled: boolean;
    onToggle: () => void;
    isDark: boolean;
}) {
    return (
        <button
            type="button"
            disabled={disabled}
            onClick={onToggle}
            className={`flex w-full items-center px-4 py-3.5 transition-opacity duration-200 ${
                disabled ? 'opacity-40' : 'active:bg-black/5 dark:active:bg-white/5'
            }`}
        >
            <span className="flex-1 text-left text-[18px]">{label}</span>
            <span
                className="rounded-[7px] px-2.5 py-1 text-[17px] tabular-nums transition-colors"
                style={active
                    ? { background: 'rgba(255,69,58,0.16)', color: '#ff453a' }
                    : {
                        background: isDark ? 'rgba(118,118,128,0.24)' : 'rgba(118,118,128,0.12)',
                        color: isDark ? '#fff' : '#000',
                    }}
            >
                {formatTime(value)}
            </span>
        </button>
    );
}
