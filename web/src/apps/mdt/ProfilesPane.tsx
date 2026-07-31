import { useEffect, useState } from 'react';
import { IdCard, Search } from 'lucide-react';

import { t } from '@/i18n';
import { colorFor } from '@/lib/format';
import { InitialsAvatar } from '@/shared/ContactAvatar';
import { EmptyState } from '@/ui/EmptyState';
import { Pill } from '@/ui/Pill';
import { useAsyncData } from '@/hooks/useAsyncData';
import { useSessionState } from '@/hooks/useSessionState';

import { PersonRecord } from './PersonRecord';
import { mdtPersonsSearch } from './mdtApi';
import { useMdtSession } from './useMdtSession';
import { mdtRowHover, mdtRowMeta, mdtRowTitle } from './mdtTheme';
import { MdtColumn } from './ui/MdtColumn';
import { MdtMaster } from './ui/MdtMaster';
import { MdtPager } from './ui/MdtPager';
import type { PersonRow } from './data';

const MIN_QUERY = 2;

export function CitizenRow({ person, selected, onPress }: {
    person:   PersonRow;
    selected: boolean;
    onPress:  () => void;
}) {
    return (
        <button
            type="button"
            onClick={onPress}
            className={`flex w-full items-center gap-3 rounded-[10px] px-3 py-2.5 text-left ${
                selected ? 'bg-ios-blue/10' : mdtRowHover
            }`}
        >
            <InitialsAvatar name={person.name} color={colorFor(person.citizenid)} size={38} />
            <span className="min-w-0 flex-1">
                <span className={`block truncate ${mdtRowTitle}`}>{person.name}</span>
                <span className={`block truncate ${mdtRowMeta}`}>
                    {[person.dob, person.citizenid].filter(Boolean).join('  ·  ')}
                </span>
            </span>
            {person.wanted && <Pill tone="red">{t('mdt.wanted', 'Wanted')}</Pill>}
        </button>
    );
}

export function ProfilesPane() {
    const { selected, select } = useMdtSession();

    const [query, setQuery] = useSessionState('mdt:profiles:query', '');
    const [page, setPage]   = useSessionState('mdt:profiles:page', 1);
    const [term, setTerm]   = useState(query.trim());

    useEffect(() => {
        const id = window.setTimeout(() => setTerm(query.trim()), 250);
        return () => window.clearTimeout(id);
    }, [query]);

    useEffect(() => { setPage(1); }, [term, setPage]);

    const { data, loading } = useAsyncData(() => mdtPersonsSearch(term, page), [term, page]);
    const rows     = data?.rows ?? [];
    const total    = data?.total ?? 0;
    const pageSize = data?.pageSize ?? 25;
    const short    = term.length < MIN_QUERY;

    const empty = short ? (
        <EmptyState
            center
            icon={Search}
            title={t('mdt.searchACitizen', 'Search for a citizen')}
            subtitle={t('mdt.searchACitizenSub', 'Type at least two characters of a name, citizen ID or phone number.')}
        />
    ) : (
        <EmptyState
            center
            icon={Search}
            title={loading ? t('mdt.searching', 'Searching') : t('mdt.noMatches', 'No matches')}
            subtitle={loading ? undefined : t('mdt.noCitizenMatch', 'Nobody on record matches that search.')}
        />
    );

    const master = (
        <MdtColumn
            className="flex-1"
            title={t('mdt.citizens', 'Citizens')}
            count={short ? undefined : total}
            query={query}
            onQuery={setQuery}
            placeholder={t('mdt.searchCitizens', 'Name, citizen ID or phone')}
            isEmpty={short || rows.length === 0}
            empty={empty}
            footer={<MdtPager page={data?.page ?? page} pageSize={pageSize} total={total} onPage={setPage} />}
        >
            <div className="flex flex-col gap-0.5">
                {rows.map(row => (
                    <CitizenRow
                        key={row.citizenid}
                        person={row}
                        selected={row.citizenid === selected}
                        onPress={() => select(row.citizenid)}
                    />
                ))}
            </div>
        </MdtColumn>
    );

    return (
        <MdtMaster
            master={master}
            detail={selected ? <PersonRecord key={selected} citizenid={selected} /> : undefined}
            placeholder={
                <EmptyState
                    center
                    icon={IdCard}
                    title={t('mdt.pickCitizenRecord', 'No record selected')}
                    subtitle={t('mdt.pickCitizenRecordSub', 'Search for a citizen and open them to see identity, flags, vehicles and priors.')}
                />
            }
            onCloseDetail={() => select(null)}
        />
    );
}
