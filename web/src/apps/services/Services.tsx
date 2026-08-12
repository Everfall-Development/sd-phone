import { useCallback, useState } from 'react';

import { useAsyncData } from '@/hooks/useAsyncData';
import { useNuiEvent } from '@/hooks/useNuiEvent';
import { useSessionState } from '@/hooks/useSessionState';
import { CompaniesTab } from './CompaniesTab';
import { ServiceMessagesTab } from './ServiceMessagesTab';
import { ServicesTabBar, type ServicesTab } from './ServicesTabBar';
import { fetchDirectory, fetchInbox, markThreadRead, type Inbox } from './servicesApi';

const EMPTY_INBOX: Inbox = { personal: [], job: [], hasJob: false };

type Scope = 'personal' | 'job';

export function Services({ onClose: _onClose }: { onClose: () => void }) {
    const [tab, setTab] = useSessionState<ServicesTab>('services:tab', 'directory');
    const activeTab: ServicesTab = tab === 'inbox' ? 'inbox' : 'directory';
    const { data: directory, settled: directoryLoaded, refetch: refreshDirectory } = useAsyncData(fetchDirectory, []);
    const { data: inboxData, settled: inboxLoaded, refetch: refreshInbox } = useAsyncData(fetchInbox, []);
    const [inboxOverride, setInboxOverride] = useState<Inbox | null>(null);
    const inbox = inboxOverride ?? inboxData ?? EMPTY_INBOX;

    useNuiEvent('sd-phone:services:inbox', useCallback(() => {
        setInboxOverride(null);
        refreshInbox();
    }, [refreshInbox]));

    const openInbox = useCallback((updatedInbox: Inbox) => {
        setInboxOverride(updatedInbox);
        setTab('inbox');
    }, [setTab]);

    const markRead = useCallback((scope: Scope, key: string) => {
        const clearUnread = (threads: Inbox['personal']) => threads.map(thread => (
            thread.key === key && thread.unread > 0 ? { ...thread, unread: 0 } : thread
        ));
        setInboxOverride(current => {
            const source = current ?? inbox;
            return scope === 'job'
                ? { ...source, job: clearUnread(source.job) }
                : { ...source, personal: clearUnread(source.personal) };
        });
        void markThreadRead(scope, key);
    }, [inbox]);

    return (
        <div className="absolute inset-0 flex flex-col bg-base font-sf">
            <div className="h-[58px] shrink-0" aria-hidden />

            <div className="flex min-h-0 flex-1 flex-col overflow-hidden">
                <div key={activeTab} className="flex min-h-0 flex-1 flex-col animate-swipe-in-left">
                    {activeTab === 'directory' ? (
                        <CompaniesTab
                            companies={directory?.companies ?? []}
                            loaded={directoryLoaded}
                            unavailable={directory?.unavailable}
                            onRetry={refreshDirectory}
                            onMessaged={openInbox}
                        />
                    ) : (
                        <ServiceMessagesTab
                            inbox={inbox}
                            loaded={inboxLoaded}
                            onInboxChange={setInboxOverride}
                            onMarkRead={markRead}
                        />
                    )}
                </div>
            </div>

            <ServicesTabBar
                tab={activeTab}
                onChange={setTab}
                inboxBadge={
                    inbox.personal.reduce((total, thread) => total + thread.unread, 0)
                    + inbox.job.reduce((total, thread) => total + thread.unread, 0)
                }
            />
        </div>
    );
}
