import { useEffect, useState } from 'react';
import { Search } from 'lucide-react';

import { t } from '@/i18n';
import { EmptyState } from '@/ui/EmptyState';
import { Scroller } from '@/ui/Scroller';
import { SearchBar } from '@/ui/SearchBar';
import { useAsyncData } from '@/hooks/useAsyncData';

import { CitizenRow } from './ProfilesPane';
import { mdtPersonsSearch } from './mdtApi';
import { MdtButton } from './ui/MdtButton';
import { MdtCard } from './ui/MdtCard';
import { MdtPager } from './ui/MdtPager';

const MIN_QUERY = 2;

export interface PickedPerson {
    citizenid: string;
    name:      string;
}

export function PersonPicker({ title, onPick, onClose }: {
    title?:  string;
    onPick:  (person: PickedPerson) => void;
    onClose: () => void;
}) {
    const [query, setQuery] = useState('');
    const [page, setPage]   = useState(1);
    const [term, setTerm]   = useState('');

    useEffect(() => {
        const id = window.setTimeout(() => { setTerm(query.trim()); setPage(1); }, 250);
        return () => window.clearTimeout(id);
    }, [query]);

    useEffect(() => {
        function onKey(e: KeyboardEvent) {
            if (e.key === 'Escape') { e.stopPropagation(); onClose(); }
        }
        window.addEventListener('keydown', onKey, true);
        return () => window.removeEventListener('keydown', onKey, true);
    }, [onClose]);

    const { data, loading } = useAsyncData(() => mdtPersonsSearch(term, page), [term, page]);
    const rows     = data?.rows ?? [];
    const total    = data?.total ?? 0;
    const pageSize = data?.pageSize ?? 25;
    const short    = term.length < MIN_QUERY;

    return (
        <div
            className="absolute inset-0 z-20 flex items-center justify-center px-6"
            style={{ background: 'rgba(0,0,0,0.32)', animation: 'ios-sheet-backdrop-in 0.2s ease-out' }}
            onClick={onClose}
        >
            <div className="w-full max-w-[440px]" onClick={e => e.stopPropagation()}>
                <MdtCard className="flex flex-col overflow-hidden">
                    <div className="flex items-center gap-3 px-4 pb-3 pt-4">
                        <span className="min-w-0 flex-1 truncate text-[17px] font-semibold text-black dark:text-white">
                            {title ?? t('mdt.pickCitizen', 'Pick a citizen')}
                        </span>
                        <MdtButton size="sm" onClick={onClose}>{t('common.cancel', 'Cancel')}</MdtButton>
                    </div>

                    <div className="px-4 pb-3">
                        <SearchBar
                            autoFocus
                            value={query}
                            onChange={setQuery}
                            placeholder={t('mdt.searchCitizens', 'Name, citizen ID or phone')}
                        />
                    </div>

                    <Scroller className="h-[320px] px-2 pb-2">
                        {short ? (
                            <EmptyState
                                center
                                icon={Search}
                                title={t('mdt.searchACitizen', 'Search for a citizen')}
                                subtitle={t('mdt.searchACitizenSub', 'Type at least two characters of a name, citizen ID or phone number.')}
                            />
                        ) : rows.length === 0 ? (
                            <EmptyState
                                center
                                icon={Search}
                                title={loading ? t('mdt.searching', 'Searching') : t('mdt.noMatches', 'No matches')}
                                subtitle={loading ? undefined : t('mdt.noCitizenMatch', 'Nobody on record matches that search.')}
                            />
                        ) : (
                            <div className="flex flex-col gap-0.5">
                                {rows.map(row => (
                                    <CitizenRow
                                        key={row.citizenid}
                                        person={row}
                                        selected={false}
                                        onPress={() => onPick({ citizenid: row.citizenid, name: row.name })}
                                    />
                                ))}
                            </div>
                        )}
                    </Scroller>

                    <MdtPager page={data?.page ?? page} pageSize={pageSize} total={total} onPage={setPage} />
                </MdtCard>
            </div>
        </div>
    );
}
