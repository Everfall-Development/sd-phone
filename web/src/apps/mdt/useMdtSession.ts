import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';

import { useAsyncData } from '@/hooks/useAsyncData';
import { useSessionState } from '@/hooks/useSessionState';
import { useDeckActive } from '@/shell/deckActive';

import { SECTION_PERMISSION } from './data';
import type { Department, MdtPermission, MdtSection, Offence, Officer } from './data';
import { mdtBootstrap } from './mdtApi';

export interface MdtSessionValue {
    me:         Officer | null;
    department: Department | null;
    offences:   Offence[];
    loading:    boolean;
    ready:      boolean;
    can:        (key: MdtPermission) => boolean;
    canOpen:    (section: MdtSection) => boolean;
    section:    MdtSection;
    setSection: (section: MdtSection) => void;
    selected:   string | null;
    select:     (ref: string | null) => void;
    open:       (section: MdtSection, ref?: string | null) => void;
    openRecord: (section: MdtSection, ref?: string | null) => void;
    setMe:      (officer: Officer) => void;
    refresh:    () => void;
}

const MdtSessionContext = createContext<MdtSessionValue | null>(null);

export const MdtSessionProvider = MdtSessionContext.Provider;

export function useMdtSession(): MdtSessionValue {
    const value = useContext(MdtSessionContext);
    if (!value) throw new Error('useMdtSession used outside the MDT session provider');
    return value;
}

export function useDeckRefresh(fn: () => void): void {
    const active = useDeckActive();
    const wasActive = useRef(active);
    const fnRef = useRef(fn);
    fnRef.current = fn;

    useEffect(() => {
        if (active && !wasActive.current) fnRef.current();
        wasActive.current = active;
    }, [active]);
}

export function useMdtSessionState(): MdtSessionValue {
    const [section, setSection] = useSessionState<MdtSection>('mdt:section', 'home');
    const [selection, setSelection] = useSessionState<Partial<Record<MdtSection, string | null>>>('mdt:selection', {});
    const [meOverride, setMeOverride] = useState<Officer | null>(null);

    const { data, loading, refetch } = useAsyncData(mdtBootstrap, []);

    useDeckRefresh(refetch);

    const grants = useMemo(() => new Set<string>(data?.grants ?? []), [data]);

    const can = useCallback((key: MdtPermission) => grants.has(key), [grants]);

    const canOpen = useCallback(
        (target: MdtSection) => grants.has(SECTION_PERMISSION[target]),
        [grants],
    );

    const select = useCallback(
        (ref: string | null) => setSelection(prev => ({ ...prev, [section]: ref })),
        [section, setSelection],
    );

    const open = useCallback((target: MdtSection, ref?: string | null) => {
        if (ref !== undefined) setSelection(prev => ({ ...prev, [target]: ref }));
        setSection(target);
    }, [setSection, setSelection]);

    const setMe = useCallback((officer: Officer) => setMeOverride(officer), []);

    const me = meOverride ?? data?.me ?? null;

    return useMemo(() => ({
        me,
        department: data?.department ?? null,
        offences:   data?.offences ?? [],
        loading,
        ready:      data !== null,
        can,
        canOpen,
        section,
        setSection,
        selected:   selection[section] ?? null,
        select,
        open,
        openRecord: open,
        setMe,
        refresh:    refetch,
    }), [me, data, loading, can, canOpen, section, setSection, selection, select, open, setMe, refetch]);
}
