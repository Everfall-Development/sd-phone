import { Bell, Heart, MessageCircle, Repeat2, UserPlus } from 'lucide-react';

import type { WidgetSize, WidgetTheme } from '@/apps/appstore/appsApi';
import { QuipMark } from '@/apps/birdy/QuipMark';
import { t } from '@/i18n';
import { WidgetTile, palette } from './WidgetTile';
import type { Palette } from './WidgetTile';
import { projectQuipActivity, type QuipActivityEntry } from './quipActivityData';
import { useQuipActivity } from './quipActivityStore';

const BRAND = '#2699f2';

function iconFor(kind: QuipActivityEntry['kind'], color: string) {
    if (kind === 'reply') return <MessageCircle className="h-[13px] w-[13px]" strokeWidth={2.2} style={{ color }} />;
    if (kind === 'like') return <Heart className="h-[13px] w-[13px]" strokeWidth={2.2} style={{ color }} />;
    if (kind === 'repost') return <Repeat2 className="h-[13px] w-[13px]" strokeWidth={2.2} style={{ color }} />;
    if (kind === 'follow') return <UserPlus className="h-[13px] w-[13px]" strokeWidth={2.2} style={{ color }} />;
    return <Bell className="h-[13px] w-[13px]" strokeWidth={2.2} style={{ color }} />;
}

function unreadLabel(count: number): string {
    return count > 99 ? '99+' : String(count);
}

function Header({ theme, unread, p }: { theme: WidgetTheme; unread: number; p: Palette }) {
    return (
        <div className="flex shrink-0 items-center justify-between gap-2">
            <div className="flex min-w-0 items-center gap-1.5">
                <QuipMark color={theme === 'light' ? 'black' : 'white'} className="h-[15px] w-[15px] shrink-0" />
                <span className="truncate text-[11px] font-semibold" style={{ color: p.sub }}>
                    {t('widgets.quip', 'Quip')}
                </span>
            </div>
            {unread > 0 && (
                <span className="flex h-[20px] min-w-[20px] shrink-0 items-center justify-center rounded-full px-1.5 text-[10px] font-bold tabular-nums text-white" style={{ background: BRAND }}>
                    {unreadLabel(unread)}
                </span>
            )}
        </div>
    );
}

function actionLabel(item: QuipActivityEntry): string {
    if (item.kind === 'reply') return t('widgets.quipReplied', 'replied to your post');
    if (item.kind === 'follow') return t('widgets.quipFollowing', 'is now following you');
    return item.action;
}

function ActivityRow({ item, p, compact = false }: { item: QuipActivityEntry; p: Palette; compact?: boolean }) {
    return (
        <div className={`flex min-w-0 ${compact ? 'gap-2 py-1.5' : 'gap-2.5 py-2'}`}>
            <div className="flex h-[24px] w-[16px] shrink-0 items-center justify-center">
                {iconFor(item.kind, BRAND)}
            </div>
            <div className="min-w-0 flex-1">
                <div className="truncate text-[11px] leading-tight" style={{ color: p.fg }}>
                    <span className="font-semibold">{item.actor}</span>{' '}{actionLabel(item)}
                </div>
                {item.preview && (
                    <div className="mt-0.5 truncate text-[10px] leading-tight" style={{ color: p.sub }}>
                        {item.preview}
                    </div>
                )}
            </div>
        </div>
    );
}

function EmptyActivity({ p }: { p: Palette }) {
    return (
        <div className="flex min-h-0 flex-1 items-center justify-center px-3 text-center text-[11px]" style={{ color: p.sub }}>
            {t('widgets.quipNoActivity', 'No recent activity')}
        </div>
    );
}

export function QuipActivityWidget({ size, width, height, theme = 'dark' }: {
    size: WidgetSize; width: number; height: number; theme?: WidgetTheme;
}) {
    const unread = useQuipActivity(s => s.unread);
    const activity = useQuipActivity(s => s.activity).map(projectQuipActivity);
    const p = palette(theme);
    const isGlass = theme === 'glass';
    const radius = size === 'sm' ? 22 : 26;

    if (size === 'sm') {
        return (
            <WidgetTile width={width} height={height} radius={radius} tint={p.bg} glass={isGlass} hairline={false}>
                <div className="flex h-full w-full flex-col justify-between p-3.5" style={{ color: p.fg }}>
                    <Header theme={theme} unread={unread} p={p} />
                    <div className="flex items-baseline gap-1">
                        <span className="text-[39px] font-semibold leading-none tabular-nums tracking-tight">{unreadLabel(unread)}</span>
                        <span className="text-[11px] font-medium" style={{ color: p.sub }}>{t('widgets.quipUnread', 'unread')}</span>
                    </div>
                </div>
            </WidgetTile>
        );
    }

    const latest = activity[0];
    if (size === 'md') {
        return (
            <WidgetTile width={width} height={height} radius={radius} tint={p.bg} glass={isGlass} hairline={false}>
                <div className="flex h-full w-full flex-col p-3.5" style={{ color: p.fg }}>
                    <Header theme={theme} unread={unread} p={p} />
                    <div className="mt-2 min-h-0 flex-1">
                        {latest ? <ActivityRow item={latest} p={p} /> : <EmptyActivity p={p} />}
                    </div>
                </div>
            </WidgetTile>
        );
    }

    return (
        <WidgetTile width={width} height={height} radius={radius} tint={p.bg} glass={isGlass} hairline={false}>
            <div className="flex h-full w-full flex-col p-3.5" style={{ color: p.fg }}>
                <Header theme={theme} unread={unread} p={p} />
                <div className="mt-2 min-h-0 flex-1 overflow-hidden">
                    {activity.length > 0
                        ? activity.slice(0, 4).map(item => <ActivityRow key={item.id} item={item} p={p} compact />)
                        : <EmptyActivity p={p} />}
                </div>
            </div>
        </WidgetTile>
    );
}
