import { describe, expect, it } from 'vitest';

import type { InboxMessage, InboxThread } from './servicesApi';
import type { Company } from './data';
import {
    buildServiceDrafts,
    filterMessageThreads,
    getCompanyMessageThread,
    getThreadIdentity,
    isNewMessageDay,
    limitServiceAttachments,
} from './messageData';

const staffThread: InboxThread = {
    key: '5551234',
    name: 'John Doe',
    color: '#0A84FF',
    emoji: '🚓',
    preview: 'Can someone get out to me?',
    ts: 1_700_000_000_000,
    unread: 2,
    messages: [
        { id: 'one', from: 'them', name: 'John Doe', body: 'Can someone get out to me?', ts: 1_700_000_000_000 },
    ],
};

const company: Company = {
    id: 'taxi_tuggers',
    name: "Tugger's Taxis",
    location: 'Downtown',
    category: 'Transportation',
    color: '#3a3a3c',
    emoji: '🚕',
    canCall: true,
    canMessage: true,
    emergency: false,
    status: 'open',
};

describe('Businesses message data', () => {
    it('shows the customer name first and the customer phone second for staff threads', () => {
        expect(getThreadIdentity(staffThread, 'job')).toEqual({
            title: 'John Doe',
            secondary: '5551234',
        });
    });

    it('falls back to the phone when the staff thread has no customer name', () => {
        expect(getThreadIdentity({ ...staffThread, name: '' }, 'job')).toEqual({ title: '5551234' });
    });

    it('searches customer names, phone numbers, and previews', () => {
        expect(filterMessageThreads([staffThread], 'john')).toHaveLength(1);
        expect(filterMessageThreads([staffThread], '5551234')).toHaveLength(1);
        expect(filterMessageThreads([staffThread], 'police')).toHaveLength(0);
        expect(filterMessageThreads([staffThread], 'get out')).toHaveLength(1);
    });

    it('opens a real empty conversation when a business has no existing thread', () => {
        expect(getCompanyMessageThread([], company)).toEqual({
            key: 'taxi_tuggers',
            name: "Tugger's Taxis",
            color: '#3a3a3c',
            emoji: '🚕',
            iconUrl: undefined,
            preview: '',
            ts: 0,
            unread: 0,
            messages: [],
        });
    });

    it('reuses the existing business conversation instead of creating a duplicate', () => {
        const existing = { ...staffThread, key: company.id, name: company.name };
        expect(getCompanyMessageThread([existing], company)).toBe(existing);
    });

    it('keeps images and text in one ordered send batch', () => {
        expect(buildServiceDrafts('  Need help  ', ['one.jpg', 'two.jpg'], '📷 Photo')).toEqual([
            { kind: 'image', mediaUrl: 'one.jpg', body: '📷 Photo' },
            { kind: 'image', mediaUrl: 'two.jpg', body: '📷 Photo' },
            { kind: 'text', body: 'Need help' },
        ]);
        expect(buildServiceDrafts('   ', [], '📷 Photo')).toEqual([]);
    });

    it('caps the attachment batch at four images', () => {
        expect(limitServiceAttachments(['one.jpg', 'two.jpg'], ['three.jpg', 'four.jpg', 'five.jpg'])).toEqual({
            accepted: ['three.jpg', 'four.jpg'],
            dropped: 1,
        });
    });

    it('drops duplicate attachments so each image has one stable preview', () => {
        expect(limitServiceAttachments(['one.jpg'], ['one.jpg', 'two.jpg', 'two.jpg'])).toEqual({
            accepted: ['two.jpg'],
            dropped: 2,
        });
    });

    it('detects message day boundaries for native conversation separators', () => {
        const first: InboxMessage = { id: 'one', from: 'them', body: 'Hi', ts: new Date(2026, 0, 10, 22).getTime() };
        const sameDay: InboxMessage = { ...first, id: 'two', ts: new Date(2026, 0, 10, 23).getTime() };
        const nextDay: InboxMessage = { ...first, id: 'three', ts: new Date(2026, 0, 11, 1).getTime() };

        expect(isNewMessageDay(undefined, first)).toBe(true);
        expect(isNewMessageDay(first, sameDay)).toBe(false);
        expect(isNewMessageDay(sameDay, nextDay)).toBe(true);
    });
});
