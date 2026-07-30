import { fetchNui, isFiveM } from '@/core/nui';
import type { Envelope } from '@/core/api';
import { VEHICLES } from './data';
import type { Vehicle } from './data';

export async function fetchVehicles(): Promise<Vehicle[]> {
    if (!isFiveM) return VEHICLES;
    const res = await fetchNui<Envelope<Vehicle[]>>('sd-phone:garages:list');
    return res?.success && Array.isArray(res.data) ? res.data : [];
}
