import type { PillTone } from '@/ui/Pill';

export const MDT_STATUS_RESERVE = 54;

export const MDT_RAIL_W = 236;
export const MDT_RAIL_W_COLLAPSED = 68;

export const MDT_ACCENT = '#1d4ed8';

export const mdtBackdrop = 'bg-[#d4d4d4] dark:bg-base';

export const mdtCardSurface = 'rounded-[16px] bg-white shadow-[0_1px_3px_rgba(0,0,0,0.06)] ring-1 ring-black/[0.04] dark:bg-surface dark:shadow-none dark:ring-white/[0.06]';

export const mdtHairline = 'bg-black/[0.13] dark:bg-white/[0.13]';
export const mdtRuleX = `h-px w-full shrink-0 ${mdtHairline}`;
export const mdtRuleY = `w-px shrink-0 ${mdtHairline}`;

export const mdtPanePad = 'px-6 pt-5';

export const mdtSectionHeader = 'text-[13px] uppercase tracking-wider text-ios-gray';
export const mdtColumnTitle = 'text-[15px] font-semibold tracking-tight text-black dark:text-white';
export const mdtRowTitle = 'text-[15px] font-semibold leading-tight text-black dark:text-white';
export const mdtRowBody = 'text-[13.5px] leading-snug text-black/70 dark:text-white/70';
export const mdtRowMeta = 'text-[12.5px] font-medium text-ios-gray';
export const mdtRef = 'text-[12.5px] font-bold uppercase tracking-wide tabular-nums text-ios-gray';

export const mdtRowHover = 'transition-colors duration-150 hover:bg-black/[0.035] active:bg-black/[0.06] dark:hover:bg-white/[0.05] dark:active:bg-white/[0.08]';

export const mdtFieldClass = 'w-full rounded-[9px] border border-black/15 bg-white px-3 py-2 text-[15px] text-black outline-none transition-colors placeholder:text-black/35 focus:border-ios-blue dark:border-white/20 dark:bg-base/40 dark:text-white dark:placeholder:text-white/35';

export const STATUS_TONE: Record<string, PillTone> = {
    open:        'blue',
    in_progress: 'orange',
    closed:      'green',
    active:      'red',
    expired:     'orange',
    valid:       'green',
    suspended:   'orange',
    impounded:   'red',
    low:         'green',
    medium:      'orange',
    high:        'red',
    suspect:     'red',
    victim:      'blue',
    witness:     'orange',
    primary:     'blue',
    assisting:   'green',
    supervisor:  'orange',
    felony:      'red',
    misdemeanor: 'orange',
    infraction:  'blue',
    wanted:         'red',
    armed:          'red',
    gang:           'orange',
    mental_health:  'orange',
    flight_risk:    'orange',
    informant:      'blue',
};
