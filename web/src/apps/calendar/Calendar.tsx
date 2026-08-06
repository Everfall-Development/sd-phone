import { useMemo, useRef, useState } from 'react';
import { Plus } from 'lucide-react';

import { useTheme } from '@/stores/themeStore';
import { useSessionState } from '@/hooks/useSessionState';
import { addMonths, dayKey, formatLongDate, formatTime } from './data';
import type { CalEvent } from './data';
import { EventEditor } from './EventEditor';
import { MonthGrid } from './MonthGrid';
import { useCalendarStore } from './store';
import { t } from '@/i18n';

const SB_H = 54;

export function Calendar({ onClose }: { onClose: () => void }) {
    const { theme } = useTheme('theme');
    const isDark = theme === 'dark';
    const today = useMemo(() => new Date(), []);
    const [selected, setSelected] = useSessionState<Date>('calendar:selectedDate', today);
    const [editing, setEditing] = useState<CalEvent | 'new' | null>(null);
    const hydrated = useRef(false);
    const centered = useRef(false);
    const events = useCalendarStore(state => state.events);
    const dayNotes = useCalendarStore(state => state.dayNotes);
    const loading = useCalendarStore(state => state.loading);
    const error = useCalendarStore(state => state.error);
    const hydrate = useCalendarStore(state => state.hydrate);
    const saveEvent = useCalendarStore(state => state.saveEvent);
    const deleteEvent = useCalendarStore(state => state.deleteEvent);
    const saveDayNote = useCalendarStore(state => state.saveDayNote);

    const months = useMemo(() => {
        const result: Date[] = [];
        for (let index = -12; index <= 12; index += 1) result.push(addMonths(today, index));
        return result;
    }, [today]);

    const selectedKey = dayKey(selected);
    const selectedEvents = useMemo(
        () => events
            .filter(event => event.dayKey === selectedKey)
            .sort((a, b) => {
                if (a.allDay && !b.allDay) return -1;
                if (b.allDay && !a.allDay) return 1;
                return (a.start ?? '').localeCompare(b.start ?? '');
            }),
        [events, selectedKey],
    );
    const selectedNote = dayNotes[selectedKey] ?? '';

    const bindRoot = useRef(function bindRoot(element: HTMLDivElement | null): void {
        if (!element || hydrated.current) return;
        hydrated.current = true;
        void hydrate();
    }).current;

    const bindTodayMonth = useRef(function bindTodayMonth(element: HTMLDivElement | null): void {
        if (!element || centered.current) return;
        centered.current = true;
        element.scrollIntoView({ block: 'start' });
    }).current;

    function selectToday(): void {
        setSelected(today);
        document.querySelector('[data-calendar-current-month="true"]')?.scrollIntoView({
            behavior: 'smooth',
            block: 'start',
        });
    }

    const dividerColor = 'rgb(var(--control))';
    const panelBackground = 'rgb(var(--surface))';
    const pageBackground = 'rgb(var(--base))';

    return (
        <div
            ref={bindRoot}
            className="absolute inset-0 z-10 flex flex-col"
            style={{ background: pageBackground, color: isDark ? '#fff' : '#000' }}
        >
            <div className="shrink-0" style={{ height: SB_H }} />

            <div className="relative z-20 flex h-11 shrink-0 items-center px-4">
                <button
                    type="button"
                    onClick={selectToday}
                    className="text-[17px] text-ios-red active:opacity-60"
                >
                    {t('calendar.today', 'Today')}
                </button>
                <div className="ml-3 min-w-0 flex-1 truncate text-center text-[13px] text-ios-gray">
                    {error ?? (loading ? t('calendar.syncing', 'Syncing…') : '')}
                </div>
                <button
                    type="button"
                    aria-label={t('calendar.newEvent', 'New event')}
                    onClick={() => setEditing('new')}
                    className="ml-auto flex h-[32px] w-[32px] items-center justify-center rounded-full text-ios-red active:opacity-60"
                >
                    <Plus className="h-[22px] w-[22px]" strokeWidth={2.5} />
                </button>
                <div className="absolute inset-x-0 bottom-0" style={{ height: 0.5, background: dividerColor }} />
            </div>

            <div className="overflow-y-auto no-scrollbar" style={{ flex: '0 0 55%' }}>
                {months.map(month => {
                    const currentMonth = month.getFullYear() === today.getFullYear()
                        && month.getMonth() === today.getMonth();
                    return (
                        <div
                            key={month.getTime()}
                            ref={currentMonth ? bindTodayMonth : undefined}
                            data-calendar-current-month={currentMonth ? 'true' : undefined}
                        >
                            <MonthGrid
                                month={month}
                                today={today}
                                selected={selected}
                                events={events}
                                onPick={setSelected}
                            />
                            <div style={{ height: 0.5, background: dividerColor, margin: '0 16px' }} />
                        </div>
                    );
                })}
            </div>

            <div className="flex flex-1 flex-col overflow-y-auto no-scrollbar">
                <div className="sticky top-0 z-10 px-4 pb-1 pt-3" style={{ background: pageBackground }}>
                    <div className="text-[15px] uppercase tracking-wider text-ios-gray">
                        {formatLongDate(selected)}
                    </div>
                </div>

                <div className="mx-4 mb-3 overflow-hidden rounded-[10px]" style={{ background: panelBackground }}>
                    <textarea
                        key={`${selectedKey}:${selectedNote}`}
                        defaultValue={selectedNote}
                        onBlur={event => void saveDayNote(selectedKey, event.target.value)}
                        placeholder={t('calendar.notesForDay', 'Notes for this day…')}
                        rows={3}
                        maxLength={4000}
                        className="w-full resize-none bg-transparent px-4 py-3 text-[17px] leading-relaxed outline-none placeholder:text-ios-gray"
                    />
                </div>

                {selectedEvents.length === 0 ? (
                    <div className="px-4 py-6 text-center text-[15px] text-ios-gray">
                        {t('calendar.noEvents', 'No Events')}
                    </div>
                ) : (
                    <div className="mx-4 mb-6 overflow-hidden rounded-[10px]" style={{ background: panelBackground }}>
                        {selectedEvents.map((event, index) => (
                            <button
                                key={event.id}
                                type="button"
                                onClick={() => setEditing(event)}
                                className="relative flex w-full items-stretch text-left active:bg-black/5 dark:active:bg-white/5"
                            >
                                <span className="w-1.5 shrink-0" style={{ background: event.color }} />
                                <div className="flex-1 px-3.5 py-3">
                                    <div className="flex items-baseline justify-between gap-2">
                                        <span className="text-[17px] font-medium">{event.title}</span>
                                        <span className="shrink-0 text-[14px] text-ios-gray">
                                            {event.allDay
                                                ? t('calendar.allDayShort', 'all-day')
                                                : event.start ? formatTime(event.start) : ''}
                                        </span>
                                    </div>
                                    {event.location ? <div className="text-[14px] text-ios-gray">{event.location}</div> : null}
                                    {event.notes ? <div className="line-clamp-2 text-[14px] text-ios-gray">{event.notes}</div> : null}
                                </div>
                                {index < selectedEvents.length - 1 ? (
                                    <div
                                        className="pointer-events-none absolute bottom-0 right-0"
                                        style={{ left: 16, height: 0.5, background: dividerColor }}
                                    />
                                ) : null}
                            </button>
                        ))}
                    </div>
                )}
            </div>

            {editing ? (
                <EventEditor
                    key={editing === 'new' ? `new-${selectedKey}` : editing.id}
                    dayKey={selectedKey}
                    dayDate={selected}
                    existing={editing === 'new' ? undefined : editing}
                    onSave={event => {
                        void saveEvent(event);
                        setEditing(null);
                    }}
                    onDelete={editing === 'new' ? undefined : () => void deleteEvent(editing.id)}
                    onClose={() => setEditing(null)}
                />
            ) : null}

            <button
                type="button"
                onClick={onClose}
                aria-label={t('calendar.closeCalendar', 'Close Calendar')}
                className="absolute inset-x-0 bottom-0 h-7 cursor-default"
            />
        </div>
    );
}
