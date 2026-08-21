import { fetchNui, isFiveM } from '@/core/nui';
import { COMPANIES, type Company, type Employee } from './data';
import { t } from '@/i18n';
import { apiData, type Envelope } from '@/core/api';


export interface Grade { level: number; label: string }

export interface MyCompany {
    job:        string;
    label:      string;
    isCompany?: boolean;
    isBoss:     boolean;
    available:  boolean;
    duty:       boolean;
    jobCalls:   boolean;
    jobMessages: boolean;
    myGrade?:   number;
    balance?:   number;
    grades?:    Grade[];
    employees?: Employee[];
}

export interface Directory {
    companies:  Company[];
    unavailable?: string;
    myCompany?: MyCompany | null;
    multijob?:  boolean;
    invoicesEnabled?: boolean;
    pendingOffers?: number;
}

interface MutResult { myCompany?: MyCompany | null }

export type ServiceResult = Envelope<MutResult>;

const DEV_DIRECTORY: Directory = { companies: COMPANIES };

function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isCompany(value: unknown): value is Company {
    if (!isRecord(value)) return false;
    if (typeof value.id !== 'string' || value.id === '') return false;
    if (typeof value.name !== 'string' || value.name === '') return false;
    if (typeof value.location !== 'string') return false;
    if (typeof value.category !== 'string' || value.category === '') return false;
    if (typeof value.color !== 'string' || typeof value.emoji !== 'string') return false;
    if (typeof value.canCall !== 'boolean' || typeof value.canMessage !== 'boolean') return false;
    if (typeof value.emergency !== 'boolean') return false;
    if (value.status !== 'open' && value.status !== 'closed') return false;
    if (value.iconUrl !== undefined && typeof value.iconUrl !== 'string') return false;
    if (value.onDuty !== undefined && typeof value.onDuty !== 'boolean') return false;
    if (value.coords !== undefined) {
        if (!isRecord(value.coords) || typeof value.coords.x !== 'number' || typeof value.coords.y !== 'number') return false;
        if (value.coords.z !== undefined && typeof value.coords.z !== 'number') return false;
    }
    return true;
}

export function isDirectoryPayload(value: unknown): value is Directory {
    if (!isRecord(value) || !Array.isArray(value.companies)) return false;
    return value.companies.every(isCompany);
}

export async function fetchDirectory(): Promise<Directory> {
    if (!isFiveM) return DEV_DIRECTORY;
    try {
        const response = await fetchNui<Envelope<Directory>>('sd-phone:services:directory');
        if (response?.success && isDirectoryPayload(response.data)) return response.data;
        return { companies: [], unavailable: response?.message ?? t('services.unavailable', 'Businesses are unavailable right now.') };
    } catch {
        return { companies: [], unavailable: t('services.unavailable', 'Businesses are unavailable right now.') };
    }
}

async function mutate(event: string, payload?: unknown): Promise<ServiceResult> {
    void event;
    void payload;
    return { success: false, message: t('services.unavailable', 'This feature is unavailable.') };
}

export const setDuty        = (on: boolean)             => mutate('sd-phone:services:setDuty', { on });
export const setJobCalls    = (on: boolean)             => mutate('sd-phone:services:setJobCalls', { on });
export const setJobMessages = (on: boolean)             => mutate('sd-phone:services:setJobMessages', { on });
export const deposit     = (amount: number)             => mutate('sd-phone:services:deposit', { amount });
export const withdraw    = (amount: number)             => mutate('sd-phone:services:withdraw', { amount });
export const hire        = (serverId: number, grade: number) => mutate('sd-phone:services:hire', { serverId, grade });
export const fire        = (citizenid: string)          => mutate('sd-phone:services:fire', { citizenid });
export const promote     = (citizenid: string)          => mutate('sd-phone:services:promote', { citizenid });
export const demote      = (citizenid: string)          => mutate('sd-phone:services:demote', { citizenid });
export const quitCompany = ()                           => mutate('sd-phone:services:quit');

export async function callCompany(job: string): Promise<ServiceResult> {
    if (!isFiveM) return { success: true };
    return (await fetchNui<ServiceResult>('sd-phone:services:callCompany', { job }))
        ?? { success: false, message: t('services.noResponse', 'No response from server') };
}

type ServiceMsgKind = 'text' | 'image' | 'location';

export interface InboxMessage {
    id:        string;
    from:      'me' | 'them';
    name?:     string;
    body:      string;
    ts:        number;
    kind?:     ServiceMsgKind;
    mediaUrl?: string;
    wpCode?:   string;
    wpSub?:    string;
}

export interface ServiceDraft {
    kind:      ServiceMsgKind;
    body:      string;
    mediaUrl?: string;
    wpCode?:   string;
    wpSub?:    string;
}
export interface InboxThread {
    key:      string;
    name:     string;
    color:    string;
    emoji:    string;
    iconUrl?: string;
    preview:  string;
    ts:       number;
    unread:   number;
    messages: InboxMessage[];
}
export interface Inbox {
    personal: InboxThread[];
    job: InboxThread[];
    hasJob: boolean;
    unavailable?: string;
}

const DEV_INBOX: Inbox = {
    personal: [
        {
            key: 'mechanic', name: 'Hayes Auto', color: '#59636E', emoji: '🔧',
            preview: 'Bring it by when you can.', ts: Date.now() - 60_000, unread: 1,
            messages: [
                { id: 'd1', from: 'me', body: 'Can you take a look at my car?', ts: Date.now() - 120_000 },
                { id: 'd2', from: 'them', name: 'Hayes Auto', body: 'Bring it by when you can.', ts: Date.now() - 60_000 },
            ],
        },
    ],
    job: [
        {
            key: '5551234', name: 'John Doe', color: '#59636E', emoji: '🔧',
            preview: 'Can you take a look at my car?', ts: Date.now() - 120_000, unread: 2,
            messages: [{ id: 'd1', from: 'them', name: 'John Doe', body: 'Can you take a look at my car?', ts: Date.now() - 120_000 }],
        },
    ],
    hasJob: true,
};

function isInboxMessage(value: unknown): value is InboxMessage {
    if (!isRecord(value)) return false;
    return typeof value.id === 'string'
        && (value.from === 'me' || value.from === 'them')
        && typeof value.body === 'string'
        && typeof value.ts === 'number';
}

function isInboxThread(value: unknown): value is InboxThread {
    if (!isRecord(value) || !Array.isArray(value.messages)) return false;
    return typeof value.key === 'string'
        && typeof value.name === 'string'
        && typeof value.color === 'string'
        && typeof value.emoji === 'string'
        && (value.iconUrl === undefined || typeof value.iconUrl === 'string')
        && typeof value.preview === 'string'
        && typeof value.ts === 'number'
        && typeof value.unread === 'number'
        && value.messages.every(isInboxMessage);
}

export function isInboxPayload(value: unknown): value is Inbox {
    if (!isRecord(value) || !Array.isArray(value.personal) || !Array.isArray(value.job)) return false;
    return typeof value.hasJob === 'boolean'
        && value.personal.every(isInboxThread)
        && value.job.every(isInboxThread);
}

export async function fetchInbox(): Promise<Inbox> {
    if (!isFiveM) return DEV_INBOX;
    try {
        const response = await fetchNui<Envelope<Inbox>>('sd-phone:services:inbox');
        if (response?.success && isInboxPayload(response.data)) return response.data;
        return {
            personal: [],
            job: [],
            hasJob: false,
            unavailable: response?.message ?? t('services.inboxUnavailable', 'Messages are unavailable right now.'),
        };
    } catch {
        return {
            personal: [],
            job: [],
            hasJob: false,
            unavailable: t('services.inboxUnavailable', 'Messages are unavailable right now.'),
        };
    }
}

export type ServiceMessageResult = Envelope<{ inbox: Inbox }>;

function messagePayload(key: 'job' | 'citizen', value: string, drafts: ServiceDraft | ServiceDraft[]): Record<string, unknown> {
    if (Array.isArray(drafts)) return { [key]: value, drafts };
    return { [key]: value, ...drafts };
}

export async function messageCompany(job: string, drafts: ServiceDraft | ServiceDraft[]): Promise<ServiceMessageResult> {
    if (!isFiveM) return { success: true, data: { inbox: DEV_INBOX } };
    return (await fetchNui<ServiceMessageResult>(
        'sd-phone:services:messageCompany',
        messagePayload('job', job, drafts),
    )) ?? { success: false, message: t('services.noResponse', 'No response from server') };
}

export async function markThreadRead(scope: 'personal' | 'job', key: string): Promise<ServiceResult> {
    if (!isFiveM) return { success: true };
    return (await fetchNui<ServiceResult>('sd-phone:services:markRead', { scope, key }))
        ?? { success: false, message: t('services.noResponse', 'No response from server') };
}

export async function replyCompany(citizen: string, drafts: ServiceDraft | ServiceDraft[]): Promise<ServiceMessageResult> {
    if (!isFiveM) return { success: true, data: { inbox: DEV_INBOX } };
    return (await fetchNui<ServiceMessageResult>(
        'sd-phone:services:replyCompany',
        messagePayload('citizen', citizen, drafts),
    )) ?? { success: false, message: t('services.noResponse', 'No response from server') };
}

export interface SavedJob {
    job:        string;
    label:      string;
    grade:      number;
    gradeLabel: string;
    active?:    boolean;
}
export interface JobInvite {
    id:         string;
    job:        string;
    label:      string;
    grade:      number;
    gradeLabel: string;
    from:       string;
}
export interface JobsView { multijob: boolean; jobs: SavedJob[]; invites: JobInvite[]; max: number }

export async function fetchJobs(): Promise<JobsView> {
    return { multijob: false, jobs: [], invites: [], max: 0 };
}

export type JobsResult = Envelope<JobsView>;
async function jobsMutate(event: string, payload?: unknown): Promise<JobsResult> {
    void event;
    void payload;
    return { success: false, message: t('services.unavailable', 'This feature is unavailable.') };
}

export const switchJob     = (job: string) => jobsMutate('sd-phone:services:switchJob', { job });
export const removeJob     = (job: string) => jobsMutate('sd-phone:services:removeJob', { job });
export const acceptInvite  = (id: string)  => jobsMutate('sd-phone:services:acceptInvite', { id });
export const declineInvite = (id: string)  => jobsMutate('sd-phone:services:declineInvite', { id });

type InvoiceStatus = 'pending' | 'paid' | 'cancelled';

export interface SentInvoice {
    id:       string;
    code?:    string;
    amount:   number;
    note:     string;
    status:   InvoiceStatus;
    toName:   string;
    toNumber: string;
    from:     string;
    ts:       number;
    paidAt?:  number;
}

export interface ReceivedInvoice {
    id:         string;
    code?:      string;
    job?:       string;
    personal?:  boolean;
    fromNumber?: string;
    label:      string;
    color:     string;
    emoji:     string;
    amount:    number;
    note:      string;
    status:    InvoiceStatus;
    from:      string;
    ts:        number;
}

const DEV_RECEIVED_INVOICES: ReceivedInvoice[] = [
    { id: 'r1', job: 'mechanic', label: 'Mechanic', color: '#3A3A3C', emoji: '⚙️', amount: 1200, note: 'Repair · engine rebuild', status: 'pending', from: 'Tommy V', ts: Date.now() - 240_000 },
    { id: 'r2', personal: true, label: '(310) 555-0199', fromNumber: '3105550199', color: '#0A84FF', emoji: '🧾', amount: 250, note: 'Dinner split', status: 'pending', from: '', ts: Date.now() - 900_000 },
    { id: 'r3', personal: true, label: '(310) 555-0148', fromNumber: '3105550148', color: '#0A84FF', emoji: '🧾', amount: 90, note: 'Fuel', status: 'paid', from: '', ts: Date.now() - 7_200_000 },
    { id: 'r4', job: 'police', label: 'Police', color: '#0A5BD3', emoji: '🚓', amount: 500, note: 'Speeding fine', status: 'cancelled', from: 'Officer Reed', ts: Date.now() - 10_800_000 },
];

export async function fetchSentInvoices(): Promise<SentInvoice[]> {
    return [];
}

export async function fetchReceivedInvoices(): Promise<ReceivedInvoice[]> {
    if (!isFiveM) return DEV_RECEIVED_INVOICES;
    return (await apiData<{ invoices: ReceivedInvoice[] }>('sd-phone:banking:invoices:received'))?.invoices ?? [];
}

export type SentInvoicesResult = Envelope<{ invoices: SentInvoice[] }>;

export async function createInvoice(target: { number?: string; serverId?: number }, amount: number, note: string): Promise<SentInvoicesResult> {
    void target;
    void amount;
    void note;
    return { success: false, message: t('services.unavailable', 'This feature is unavailable.') };
}

export async function cancelInvoice(id: string): Promise<SentInvoicesResult> {
    void id;
    return { success: false, message: t('services.unavailable', 'This feature is unavailable.') };
}

export type PayInvoiceResult = Envelope<{ balance: number; invoices: ReceivedInvoice[] }>;

export async function payInvoice(id: string): Promise<PayInvoiceResult> {
    if (!isFiveM) {
        const inv = DEV_RECEIVED_INVOICES.find(i => i.id === id);
        if (inv) inv.status = 'paid';
        return { success: true, data: { balance: 0, invoices: [...DEV_RECEIVED_INVOICES] } };
    }
    return (await fetchNui<PayInvoiceResult>('sd-phone:banking:invoices:pay', { id }))
        ?? { success: false, message: t('services.noResponse', 'No response from server') };
}
