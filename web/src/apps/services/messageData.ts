import { formatPhone } from '@/apps/phone/data';
import type { InboxMessage, InboxThread, ServiceDraft } from './servicesApi';

export type MessageScope = 'personal' | 'job';
export const MAX_SERVICE_ATTACHMENTS = 4;

export interface ThreadIdentity {
    title: string;
    secondary?: string;
}

export interface ServiceSendFeedback {
    success: boolean;
    message?: string;
}

export interface AttachmentSelection {
    accepted: string[];
    dropped: number;
}

export function getThreadIdentity(
    thread: InboxThread,
    scope: MessageScope,
    formatNumber: (number: string) => string = formatPhone,
): ThreadIdentity {
    const title = thread.name.trim() || formatNumber(thread.key);
    if (scope !== 'job') return { title };

    const phone = formatNumber(thread.key);
    return phone && phone !== title ? { title, secondary: phone } : { title };
}

export function filterMessageThreads(threads: readonly InboxThread[], query: string): InboxThread[] {
    const search = query.trim().toLocaleLowerCase();
    if (!search) return [...threads];

    return threads.filter(thread => {
        const threadText = `${thread.name} ${thread.key} ${thread.preview}`.toLocaleLowerCase();
        return threadText.includes(search);
    });
}

export function buildServiceDrafts(body: string, attachments: readonly string[], photoLabel: string): ServiceDraft[] {
    const drafts = attachments.map(mediaUrl => createImageDraft(mediaUrl, photoLabel));
    const text = body.trim();
    if (text) drafts.push({ kind: 'text', body: text });
    return drafts;
}

export function limitServiceAttachments(existing: readonly string[], selected: readonly string[]): AttachmentSelection {
    const remaining = Math.max(0, MAX_SERVICE_ATTACHMENTS - existing.length);
    const seen = new Set(existing);
    const unique = selected.filter(url => {
        if (seen.has(url)) return false;
        seen.add(url);
        return true;
    });
    const accepted = unique.slice(0, remaining);
    return { accepted, dropped: selected.length - accepted.length };
}

function createImageDraft(mediaUrl: string, body: string): ServiceDraft {
    return { kind: 'image', mediaUrl, body };
}

export function isNewMessageDay(previous: InboxMessage | undefined, current: InboxMessage): boolean {
    if (!previous) return true;
    const previousDate = new Date(previous.ts);
    const currentDate = new Date(current.ts);
    return previousDate.getFullYear() !== currentDate.getFullYear()
        || previousDate.getMonth() !== currentDate.getMonth()
        || previousDate.getDate() !== currentDate.getDate();
}
