import { useState } from 'react';

import { useAsyncData } from '@/hooks/useAsyncData';
import { useNuiEvent } from '@/hooks/useNuiEvent';
import { useSessionState } from '@/hooks/useSessionState';
import {
    clearBusinessesTarget,
    isBusinessesCompanyTarget,
    isBusinessesThreadTarget,
    useBusinessesNonce,
    useBusinessesTarget,
} from '@/shell/deeplink';
import { CompaniesTab } from './CompaniesTab';
import type { Company } from './data';
import { ServiceMessagesTab } from './ServiceMessagesTab';
import { ServicesTabBar, type ServicesTab } from './ServicesTabBar';
import { fetchDirectory, fetchInbox, markThreadRead, type Inbox } from './servicesApi';

const EMPTY_INBOX: Inbox = { personal: [], job: [], hasJob: false };

type Scope = 'personal' | 'job';

export function Services({ onClose: _onClose }: { onClose: () => void }) {
    const [tab, setTab] = useSessionState<ServicesTab>('services:tab', 'directory');
    const businessesTarget = useBusinessesTarget();
    const businessesNonce = useBusinessesNonce();
    const companyTarget = isBusinessesCompanyTarget(businessesTarget) ? businessesTarget : null;
    const threadTarget = isBusinessesThreadTarget(businessesTarget) ? businessesTarget : null;
    const {
        data: directory,
        loading: directoryLoading,
        settled: directoryLoaded,
        refetch: refreshDirectory,
    } = useAsyncData(fetchDirectory, []);
    const {
        data: inboxData,
        loading: inboxLoading,
        settled: inboxLoaded,
        refetch: refreshInbox,
    } = useAsyncData(fetchInbox, []);
    const [inboxOverride, setInboxOverride] = useState<Inbox | null>(null);
    const [composeCompany, setComposeCompany] = useState<Company | null>(null);
    const inbox = inboxOverride ?? inboxData ?? EMPTY_INBOX;
    const activeTab: ServicesTab =
        composeCompany !== null || threadTarget !== null || (companyTarget === null && tab === 'inbox')
            ? 'inbox'
            : 'directory';

    useNuiEvent('sd-phone:services:inbox', () => {
        setInboxOverride(null);
        refreshInbox();
    });

    useNuiEvent('sd-phone:services:jobsChanged', () => {
        setInboxOverride(null);
        refreshDirectory();
        refreshInbox();
    });

    useNuiEvent('sd-phone:services:directoryChanged', () => {
        refreshDirectory();
    });

    function openCompanyMessages(company: Company) {
        clearBusinessesTarget();
        setComposeCompany(company);
        setTab('inbox');
    }

    function markRead(scope: Scope, key: string) {
        function clearUnread(threads: Inbox['personal']) {
            return threads.map((thread) =>
                thread.key === key && thread.unread > 0 ? { ...thread, unread: 0 } : thread,
            );
        }
        setInboxOverride((current) => {
            const source = current ?? inbox;
            return scope === 'job'
                ? { ...source, job: clearUnread(source.job) }
                : { ...source, personal: clearUnread(source.personal) };
        });
        void markThreadRead(scope, key).then((result) => {
            if (result.success) return;
            setInboxOverride(null);
            refreshInbox();
        });
    }

    function retryInbox() {
        setInboxOverride(null);
        refreshInbox();
    }

    function changeTab(next: ServicesTab) {
        setComposeCompany(null);
        clearBusinessesTarget();
        setTab(next);
    }

    function dismissCompanyTarget() {
        setTab('directory');
        clearBusinessesTarget();
    }

    return (
        <div className="absolute inset-0 flex flex-col bg-base font-sf">
            <div className="h-[58px] shrink-0" aria-hidden />

            <div className="flex min-h-0 flex-1 flex-col overflow-hidden">
                <div className="flex min-h-0 flex-1 flex-col">
                    {activeTab === 'directory' ? (
                        <CompaniesTab
                            companies={directory?.companies ?? []}
                            loaded={directoryLoaded}
                            loading={directoryLoading}
                            unavailable={directory?.unavailable}
                            onRetry={refreshDirectory}
                            onMessage={openCompanyMessages}
                            target={companyTarget}
                            targetNonce={businessesNonce}
                            onTargetDismiss={dismissCompanyTarget}
                        />
                    ) : (
                        <ServiceMessagesTab
                            inbox={inbox}
                            loaded={inboxLoaded}
                            loading={inboxLoading}
                            unavailable={inbox.unavailable}
                            onRetry={retryInbox}
                            onInboxChange={setInboxOverride}
                            onMarkRead={markRead}
                            target={threadTarget}
                            targetNonce={businessesNonce}
                            onTargetDismiss={clearBusinessesTarget}
                            composeCompany={composeCompany}
                            onComposeDismiss={() => setComposeCompany(null)}
                        />
                    )}
                </div>
            </div>

            <ServicesTabBar
                tab={activeTab}
                onChange={changeTab}
                inboxBadge={
                    inbox.personal.reduce((total, thread) => total + thread.unread, 0) +
                    inbox.job.reduce((total, thread) => total + thread.unread, 0)
                }
            />
        </div>
    );
}
