import type { Company } from '@/apps/services/data';
import type { Inbox, InboxThread } from '@/apps/services/servicesApi';

export interface NearbyBusiness extends Company {
    distance: number | null;
}

function distanceFrom(here: { x: number; y: number } | null, company: Company): number | null {
    if (!here || !company.coords) return null;
    return Math.hypot(company.coords.x - here.x, company.coords.y - here.y);
}

export function nearbyOpenBusinesses(
    companies: Company[],
    here: { x: number; y: number } | null,
): NearbyBusiness[] {
    const candidates: NearbyBusiness[] = [];

    for (const company of companies) {
        if (company.status !== 'open' || company.emergency) continue;
        candidates.push({ ...company, distance: distanceFrom(here, company) });
    }

    return candidates.sort((left, right) => {
        if (left.distance === null && right.distance === null) return left.name.localeCompare(right.name);
        if (left.distance === null) return 1;
        if (right.distance === null) return -1;
        return left.distance - right.distance;
    });
}

export function prioritizedBusinessThreads(inbox: Inbox | null): InboxThread[] {
    if (!inbox?.hasJob) return [];
    return [...inbox.job].sort((left, right) => {
        if (left.unread !== right.unread) return right.unread - left.unread;
        return right.ts - left.ts;
    });
}
