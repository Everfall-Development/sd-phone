import { describe, expect, it } from 'vitest';

import { COMPANIES, filterBusinesses, type Company } from './data';
import { isDirectoryPayload, isInboxPayload } from './servicesApi';
import {
    isBusinessesTarget,
    onOpenMaps,
    requestOpenMaps,
    takeMapsTarget,
    type MapsTarget,
} from '@/shell/deeplink';

describe('Businesses directory', () => {
    it('keeps the stable directory DTO fields for every listing', () => {
        for (const company of COMPANIES) {
            expect(company.id).not.toBe('');
            expect(company.name).not.toBe('');
            expect(company.category).not.toBe('');
            expect(['open', 'closed']).toContain(company.status);
            expect(typeof company.canCall).toBe('boolean');
            expect(typeof company.canMessage).toBe('boolean');
            expect(typeof company.emergency).toBe('boolean');
        }
    });

    it('searches names, categories, and locations case-insensitively', () => {
        expect(filterBusinesses(COMPANIES, 'hayes', 'All').map(company => company.id)).toEqual(['mechanic']);
        expect(filterBusinesses(COMPANIES, 'dynasty', 'All').map(company => company.id)).toEqual(['realestate']);
        expect(filterBusinesses(COMPANIES, 'transport', 'All').map(company => company.id)).toEqual(['taxi']);
    });

    it('combines search with an exact compact category filter', () => {
        expect(filterBusinesses(COMPANIES, 'taxi', 'Automotive')).toEqual([]);
    });

    it('can show only open businesses', () => {
        expect(filterBusinesses(COMPANIES, '', 'All', 'open').map(company => company.id)).toEqual([
            'taxi',
            'realestate',
        ]);
    });

    it('sorts open businesses before closed businesses', () => {
        expect(filterBusinesses(COMPANIES, '', 'All').map(company => company.id)).toEqual([
            'taxi',
            'realestate',
            'mechanic',
        ]);
    });

    it('puts emergency listings before ordinary businesses without changing open-state filtering', () => {
        const emergency: Company = {
            ...COMPANIES[0],
            id: 'police',
            name: 'Police',
            category: 'Emergency',
            emergency: true,
            status: 'closed',
        };
        expect(filterBusinesses([...COMPANIES, emergency], '', 'All').map(company => company.id)).toEqual([
            'police',
            'taxi',
            'realestate',
            'mechanic',
        ]);
        expect(filterBusinesses([...COMPANIES, emergency], '', 'All', 'open').map(company => company.id)).toEqual([
            'taxi',
            'realestate',
        ]);
    });

    it('rejects malformed runtime payloads instead of rendering partial directory or inbox data', () => {
        expect(isDirectoryPayload({ companies: COMPANIES })).toBe(true);
        expect(isDirectoryPayload({ companies: [{ id: 'broken' }] })).toBe(false);
        expect(isInboxPayload({ personal: [], job: [], hasJob: false })).toBe(true);
        expect(isInboxPayload({ personal: [], job: [{ key: 'broken' }], hasJob: true })).toBe(false);
        expect(isBusinessesTarget({ scope: 'job', thread: '5550100' })).toBe(true);
        expect(isBusinessesTarget({ scope: 'job', thread: '' })).toBe(false);
    });

    it('publishes every business Maps request after earlier targets are consumed', () => {
        const opened: MapsTarget[] = [];
        const unsubscribe = onOpenMaps(() => {
            const target = takeMapsTarget();
            if (target) opened.push(target);
        });

        try {
            requestOpenMaps({ label: 'Hayes Auto', x: -1421.4, y: -450.2, companyId: 'mechanic' });
            requestOpenMaps({ label: 'Dynasty 8', x: -716.8, y: 261.5, companyId: 'realestate' });
        } finally {
            unsubscribe();
        }

        expect(opened.map(target => target.companyId)).toEqual(['mechanic', 'realestate']);
    });
});
