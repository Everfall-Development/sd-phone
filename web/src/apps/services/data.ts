import { formatMoney } from '@/lib/money';

export interface Company {
    id:          string;
    name:        string;
    location:    string;
    category:    string;
    color:       string;
    emoji:       string;
    iconUrl?:    string;
    canCall:     boolean;
    canMessage:  boolean;
    emergency:   boolean;
    status:      'open' | 'closed';
    coords?:     { x: number; y: number; z: number };
    onDuty?:     boolean;
}

export type BusinessAvailability = 'all' | 'open';

export interface Employee {
    id:     string;
    name:   string;
    rank:   string;
    online: boolean;
    status?: 'duty' | 'offduty' | 'away';
    grade?: number;
    self?:  boolean;
}

export const COMPANIES: Company[] = [
    { id: 'police', name: 'Police', location: 'Mission Row', category: 'Emergency', color: '#0A84FF', emoji: '🚓', canCall: true, canMessage: true, emergency: true, status: 'open', onDuty: true, coords: { x: 425.1, y: -979.5, z: 30.7 } },
    { id: 'ambulance', name: 'Ambulance', location: 'Pillbox Hill', category: 'Emergency', color: '#C0392B', emoji: '🚑', canCall: true, canMessage: true, emergency: true, status: 'open', onDuty: true, coords: { x: 307.7, y: -1433.4, z: 29.9 } },
    { id: 'mechanic', name: 'Hayes Auto', location: 'Strawberry Avenue', category: 'Automotive', color: '#59636E', emoji: '🔧', canCall: true, canMessage: true, emergency: false, status: 'closed', onDuty: false, coords: { x: -347.3, y: -133.8, z: 39.0 } },
    { id: 'taxi', name: 'Downtown Cab Co.', location: 'Tangerine Street', category: 'Transport', color: '#27AE60', emoji: '🚕', canCall: true, canMessage: true, emergency: false, status: 'open', onDuty: true, coords: { x: 895.7, y: -179.3, z: 74.7 } },
];

export const EMPLOYEES: Employee[] = [
    { id: 'e1', name: 'Marcus',       rank: 'Officer',    online: true,  status: 'duty'    },
    { id: 'e2', name: 'Tommy V',      rank: 'Sergeant',   online: true,  status: 'offduty' },
    { id: 'e3', name: 'Kash',         rank: 'Lieutenant', online: false, status: 'away'    },
];

export const COMPANY_BALANCE = 1_000_000;

export function filterBusinesses(
    companies: Company[],
    query: string,
    category: string,
    availability: BusinessAvailability = 'all',
): Company[] {
    const search = query.trim().toLocaleLowerCase();
    return companies
        .filter(company => {
            if (availability === 'open' && company.status !== 'open') return false;
            if (category !== 'All' && company.category !== category) return false;
            if (!search) return true;
            return `${company.name} ${company.category} ${company.location}`.toLocaleLowerCase().includes(search);
        })
        .sort((left, right) => {
            if (left.status !== right.status) return left.status === 'open' ? -1 : 1;
            if (left.emergency !== right.emergency) return left.emergency ? -1 : 1;
            const byName = left.name.localeCompare(right.name);
            return byName !== 0 ? byName : left.id.localeCompare(right.id);
        });
}

export function fmtMoney(n: number): string {
    return formatMoney(n, { whole: true });
}
