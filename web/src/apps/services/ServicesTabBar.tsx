import { Building2, MessageSquare } from 'lucide-react';

import { TabBar, type TabBarItem } from '@/ui/TabBar';
import { t } from '@/i18n';

export type ServicesTab = 'directory' | 'inbox';

export function ServicesTabBar({ tab, onChange, inboxBadge = 0 }: {
    tab: ServicesTab;
    onChange: (tab: ServicesTab) => void;
    inboxBadge?: number;
}) {
    const tabs: TabBarItem<ServicesTab>[] = [
        {
            id: 'directory',
            label: t('services.directory', 'Directory'),
            icon: active => <Building2 className="h-[33px] w-[33px]" strokeWidth={active ? 2.2 : 1.9} />,
        },
        {
            id: 'inbox',
            label: t('services.inbox', 'Inbox'),
            icon: active => <MessageSquare className="h-[33px] w-[33px]" strokeWidth={active ? 2.2 : 1.9} />,
            badge: inboxBadge,
        },
    ];

    return <TabBar tabs={tabs} active={tab} onChange={onChange} />;
}
