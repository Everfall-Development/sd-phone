import type { ReactNode } from 'react';

import { t } from '@/i18n';

export interface TabBarItem<T extends string> {
    id:    T;
    label: string;
    icon:  (active: boolean) => ReactNode;
    badge?: number;
}

export function TabBar<T extends string>({ tabs, active, onChange, labelClassName = 'text-[15px] font-bold tracking-tight', forceDark = false, activeClassName = 'text-ios-blue' }: {
    tabs:     TabBarItem<T>[];
    active:   T;
    onChange: (id: T) => void;
    labelClassName?: string;
    forceDark?: boolean;
    activeClassName?: string;
}) {
    const bar = (
        <div className="shrink-0 border-t border-black/10 bg-elevated pb-9 pt-2.5 dark:border-white/10 dark:bg-base">
            <div className="flex items-stretch justify-around px-1">
                {tabs.map(tab => {
                    const isActive = tab.id === active;
                    return (
                        <button
                            key={tab.id}
                            type="button"
                            onClick={() => onChange(tab.id)}
                            className={`flex flex-1 flex-col items-center gap-1.5 py-1 ${
                                isActive ? activeClassName : 'text-black/60 dark:text-white/60'
                            }`}
                        >
                            <span className="relative inline-flex">
                                {tab.icon(isActive)}
                                {(tab.badge ?? 0) > 0 && (
                                    <span
                                        className="absolute -right-2 -top-1 flex h-[18px] min-w-[18px] items-center justify-center rounded-full bg-ios-red px-1 text-[11px] font-bold leading-none text-white ring-2 ring-elevated dark:ring-base"
                                        aria-label={t('shell.unreadMessagesCount', '{count} unread messages', { count: tab.badge ?? 0 })}
                                    >
                                        {(tab.badge ?? 0) > 99 ? '99+' : tab.badge}
                                    </span>
                                )}
                            </span>
                            <span className={labelClassName}>{tab.label}</span>
                        </button>
                    );
                })}
            </div>
        </div>
    );
    return forceDark ? <div className="dark contents">{bar}</div> : bar;
}
