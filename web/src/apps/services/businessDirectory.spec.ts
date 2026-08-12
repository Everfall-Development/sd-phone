import { describe, expect, it } from 'vitest';

import { COMPANIES, filterBusinesses } from './data';

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
        expect(filterBusinesses(COMPANIES, 'EMERGENCY', 'All').map(company => company.id)).toEqual(['police', 'ambulance']);
        expect(filterBusinesses(COMPANIES, 'transport', 'All').map(company => company.id)).toEqual(['taxi']);
    });

    it('combines search with an exact compact category filter', () => {
        expect(filterBusinesses(COMPANIES, '', 'Emergency').map(company => company.id)).toEqual(['police', 'ambulance']);
        expect(filterBusinesses(COMPANIES, 'ambulance', 'Automotive')).toEqual([]);
    });
});
