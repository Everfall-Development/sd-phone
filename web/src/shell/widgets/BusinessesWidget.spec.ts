import { describe, expect, it } from 'vitest';

import type { Company } from '@/apps/services/data';
import type { Inbox } from '@/apps/services/servicesApi';
import { isBusinessesTarget } from '@/shell/deeplink';
import { nearbyOpenBusinesses, prioritizedBusinessThreads } from './businessesWidgetData';

const companies: Company[] = [
    {
        id: 'police',
        name: 'Police',
        location: 'Emergency',
        category: 'Emergency',
        color: '#00f',
        emoji: 'P',
        canCall: true,
        canMessage: true,
        emergency: true,
        status: 'open',
        coords: { x: 5, y: 0, z: 0 },
    },
    {
        id: 'far',
        name: 'Far Shop',
        location: 'Retail',
        category: 'Retail',
        color: '#fff',
        emoji: 'F',
        canCall: true,
        canMessage: true,
        emergency: false,
        status: 'open',
        coords: { x: 500, y: 0, z: 0 },
    },
    {
        id: 'near',
        name: 'Near Shop',
        location: 'Retail',
        category: 'Retail',
        color: '#fff',
        emoji: 'N',
        canCall: true,
        canMessage: true,
        emergency: false,
        status: 'open',
        coords: { x: 100, y: 0, z: 0 },
    },
    {
        id: 'closed',
        name: 'Closed Shop',
        location: 'Retail',
        category: 'Retail',
        color: '#fff',
        emoji: 'C',
        canCall: true,
        canMessage: true,
        emergency: false,
        status: 'closed',
        coords: { x: 1, y: 0, z: 0 },
    },
];

describe('Businesses widget projections', () => {
    it('prefers non-emergency open businesses and sorts them by distance', () => {
        expect(nearbyOpenBusinesses(companies, { x: 0, y: 0 }).map((company) => company.id)).toEqual(['near', 'far']);
    });

    it('never treats emergency services as businesses', () => {
        expect(nearbyOpenBusinesses([companies[0]], { x: 0, y: 0 })).toEqual([]);
    });

    it('keeps every candidate until after nearest sorting', () => {
        const many = Array.from(
            { length: 60 },
            (_, index): Company => ({
                id: `business-${index}`,
                name: `Business ${index}`,
                location: 'Retail',
                category: 'Retail',
                color: '#fff',
                emoji: 'B',
                canCall: true,
                canMessage: true,
                emergency: false,
                status: 'open',
                coords: { x: 60 - index, y: 0, z: 0 },
            }),
        );

        expect(nearbyOpenBusinesses(many, { x: 0, y: 0 })[0]?.id).toBe('business-59');
        expect(nearbyOpenBusinesses(many, null)).toHaveLength(60);
    });

    it('orders staff threads by unread count and then recency', () => {
        const inbox: Inbox = {
            personal: [],
            hasJob: true,
            job: [
                {
                    key: 'a',
                    name: 'A',
                    color: '#fff',
                    emoji: 'A',
                    preview: '',
                    ts: 100,
                    unread: 1,
                    messages: [],
                },
                {
                    key: 'b',
                    name: 'B',
                    color: '#fff',
                    emoji: 'B',
                    preview: '',
                    ts: 90,
                    unread: 2,
                    messages: [],
                },
                {
                    key: 'c',
                    name: 'C',
                    color: '#fff',
                    emoji: 'C',
                    preview: '',
                    ts: 110,
                    unread: 1,
                    messages: [],
                },
            ],
        };

        expect(prioritizedBusinessThreads(inbox).map((thread) => thread.key)).toEqual(['b', 'c', 'a']);
    });

    it('does not expose personal threads as a staff queue', () => {
        const inbox: Inbox = {
            personal: [
                {
                    key: 'personal',
                    name: 'Personal',
                    color: '#fff',
                    emoji: 'P',
                    preview: '',
                    ts: 1,
                    unread: 3,
                    messages: [],
                },
            ],
            job: [],
            hasJob: false,
        };

        expect(prioritizedBusinessThreads(inbox)).toEqual([]);
    });

    it('accepts exact business and thread targets without accepting partial entities', () => {
        expect(
            isBusinessesTarget({
                route: 'directory',
                entityType: 'business',
                entityId: 'hayes',
            }),
        ).toBe(true);
        expect(
            isBusinessesTarget({
                route: 'inbox',
                entityType: 'thread',
                entityId: '5551234',
                scope: 'job',
                thread: '5551234',
            }),
        ).toBe(true);
        expect(isBusinessesTarget({ route: 'directory', entityType: 'business' })).toBe(false);
    });
});
