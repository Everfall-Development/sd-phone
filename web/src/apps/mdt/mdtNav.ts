import {
    Car, ClipboardList, FileText, FolderOpen, Gavel, HeartPulse, IdCard,
    LayoutDashboard, Lock, MessageSquare, RadioTower, Scale, ScrollText, Users, type LucideIcon,
} from 'lucide-react';

import { t } from '@/i18n';
import type { MdtSection } from './data';

export interface MdtNavItem {
    id:    MdtSection;
    label: string;
    icon:  LucideIcon;
}

export function navItems(): Record<MdtSection, MdtNavItem> {
    return {
        home:      { id: 'home',      label: t('mdt.navHome', 'Home'),           icon: LayoutDashboard },
        dispatch:  { id: 'dispatch',  label: t('mdt.navDispatch', 'Dispatch'),   icon: RadioTower },
        profiles:  { id: 'profiles',  label: t('mdt.navProfiles', 'Profiles'),   icon: IdCard },
        vehicles:  { id: 'vehicles',  label: t('mdt.navVehicles', 'Vehicles'),   icon: Car },
        reports:   { id: 'reports',   label: t('mdt.navReports', 'Reports'),     icon: FileText },
        cases:     { id: 'cases',     label: t('mdt.navCases', 'Cases'),         icon: FolderOpen },
        warrants:  { id: 'warrants',  label: t('mdt.navWarrants', 'Warrants'),   icon: Gavel },
        offences:  { id: 'offences',  label: t('mdt.navOffences', 'Offences'),   icon: Scale },
        employees: { id: 'employees', label: t('mdt.navEmployees', 'Employees'), icon: Users },
        chat:      { id: 'chat',      label: t('mdt.navChat', 'Chat'),           icon: MessageSquare },
        jail:      { id: 'jail',      label: t('mdt.navJail', 'Jail'),           icon: Lock },
        logs:      { id: 'logs',      label: t('mdt.navLogs', 'Logs'),           icon: ScrollText },
        patients:  { id: 'patients',  label: t('mdt.navPatients', 'Patients'),   icon: HeartPulse },
        protocols: { id: 'protocols', label: t('mdt.navProtocols', 'Protocols'), icon: ClipboardList },
    };
}
