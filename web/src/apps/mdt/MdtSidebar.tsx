import {
    Car, ChevronLeft, ChevronRight, FileText, FolderOpen, Gavel, IdCard, LayoutDashboard, Lock,
    MessageSquare, RadioTower, Scale, ScrollText, Users, type LucideIcon,
} from 'lucide-react';

import { t } from '@/i18n';
import { Scroller } from '@/ui/Scroller';
import { useSessionState } from '@/hooks/useSessionState';
import type { MdtSection } from './data';
import { MDT_ACCENT, MDT_RAIL_W, MDT_RAIL_W_COLLAPSED, mdtRuleY } from './mdtTheme';
import { useMdtSession } from './useMdtSession';

interface RailItem {
    id:    MdtSection;
    label: string;
    icon:  LucideIcon;
}

function items(): RailItem[] {
    return [
        { id: 'home',      label: t('mdt.navHome', 'Home'),           icon: LayoutDashboard },
        { id: 'dispatch',  label: t('mdt.navDispatch', 'Dispatch'),   icon: RadioTower },
        { id: 'profiles',  label: t('mdt.navProfiles', 'Profiles'),   icon: IdCard },
        { id: 'vehicles',  label: t('mdt.navVehicles', 'Vehicles'),   icon: Car },
        { id: 'reports',   label: t('mdt.navReports', 'Reports'),     icon: FileText },
        { id: 'cases',     label: t('mdt.navCases', 'Cases'),         icon: FolderOpen },
        { id: 'warrants',  label: t('mdt.navWarrants', 'Warrants'),   icon: Gavel },
        { id: 'offences',  label: t('mdt.navOffences', 'Offences'),   icon: Scale },
        { id: 'employees', label: t('mdt.navEmployees', 'Employees'), icon: Users },
        { id: 'chat',      label: t('mdt.navChat', 'Chat'),           icon: MessageSquare },
        { id: 'jail',      label: t('mdt.navJail', 'Jail'),           icon: Lock },
        { id: 'logs',      label: t('mdt.navLogs', 'Logs'),           icon: ScrollText },
    ];
}

export function MdtSidebar({ compact = false }: { compact?: boolean }) {
    const { canOpen, section, setSection, department } = useMdtSession();
    const [railOpen, setRailOpen] = useSessionState('mdt:railOpen', true);

    const open = railOpen && !compact;
    const accent = department?.accent ?? MDT_ACCENT;
    const visible = items().filter(item => item.id === 'home' || canOpen(item.id));

    return (
        <div className="relative flex shrink-0">
            <div
                className="flex min-h-0 flex-col overflow-hidden transition-[width] duration-200 ease-out"
                style={{ width: open ? MDT_RAIL_W : MDT_RAIL_W_COLLAPSED }}
            >
                <Scroller className="min-h-0 flex-1 px-3 pb-6 pt-3">
                    <div className="flex flex-col gap-[3px]">
                        {visible.map(item => {
                            const Icon = item.icon;
                            const active = section === item.id;
                            return (
                                <button
                                    key={item.id}
                                    type="button"
                                    onClick={() => setSection(item.id)}
                                    title={open ? undefined : item.label}
                                    aria-label={item.label}
                                    aria-current={active ? 'page' : undefined}
                                    className={`flex items-center rounded-[10px] transition-colors duration-150 ${
                                        open ? 'gap-3 px-3 py-[9px]' : 'justify-center px-0 py-[10px]'
                                    } ${
                                        active
                                            ? 'text-white'
                                            : 'text-black hover:bg-black/[0.05] active:bg-black/[0.09] dark:text-white dark:hover:bg-white/[0.07] dark:active:bg-white/[0.11]'
                                    }`}
                                    style={active ? { background: accent } : undefined}
                                >
                                    <Icon
                                        className="h-5 w-5 shrink-0"
                                        strokeWidth={active ? 2.3 : 1.9}
                                        style={active ? undefined : { opacity: 0.72 }}
                                    />
                                    {open && (
                                        <span className="min-w-0 flex-1 truncate text-left text-[15px] font-medium tracking-tight">
                                            {item.label}
                                        </span>
                                    )}
                                </button>
                            );
                        })}
                    </div>
                </Scroller>
            </div>

            <div className={mdtRuleY} />

            {!compact && (
                <button
                    type="button"
                    onClick={() => setRailOpen(o => !o)}
                    aria-label={open ? t('mdt.collapseSidebar', 'Collapse sidebar') : t('mdt.expandSidebar', 'Expand sidebar')}
                    className="absolute right-0 top-1/2 z-10 flex h-[46px] w-[15px] -translate-y-1/2 translate-x-1/2 items-center justify-center rounded-full bg-white text-ios-gray shadow-[0_1px_4px_rgba(0,0,0,0.14)] ring-1 ring-black/[0.06] transition-colors duration-150 hover:text-black active:bg-[#f0f0f2] dark:bg-elevated dark:ring-white/[0.08] dark:hover:text-white"
                >
                    {open
                        ? <ChevronLeft className="h-[13px] w-[13px]" strokeWidth={2.6} />
                        : <ChevronRight className="h-[13px] w-[13px]" strokeWidth={2.6} />}
                </button>
            )}
        </div>
    );
}
