import { useEffect, useState } from 'react';
import { HeartPulse, Search } from 'lucide-react';

import { t } from '@/i18n';
import { colorFor } from '@/lib/format';
import { InitialsAvatar } from '@/shared/ContactAvatar';
import { EmptyState } from '@/ui/EmptyState';
import { Pill } from '@/ui/Pill';
import { useAsyncData } from '@/hooks/useAsyncData';
import { useSessionState } from '@/hooks/useSessionState';

import { PatientRecord } from './PatientRecord';
import { mdtPatientsSearch } from './mdtApi';
import { useMdtSession } from './useMdtSession';
import { mdtRowHover, mdtRowMeta, mdtRowTitle } from './mdtTheme';
import { MdtColumn } from './ui/MdtColumn';
import { MdtMaster } from './ui/MdtMaster';
import { MdtPager } from './ui/MdtPager';
import type { PatientRow } from './data';

const MIN_QUERY = 2;

function PatientListRow({ patient, selected, onPress }: {
    patient:  PatientRow;
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
            <InitialsAvatar name={patient.name} color={colorFor(patient.citizenid)} size={38} />
            <span className="min-w-0 flex-1">
                <span className={`block truncate ${mdtRowTitle}`}>{patient.name}</span>
                <span className={`block truncate ${mdtRowMeta}`}>
                    {[patient.dob, patient.citizenid].filter(Boolean).join('  ·  ')}
                </span>
            </span>
            {patient.dnr && <Pill tone="red">{t('mdt.dnr', 'DNR')}</Pill>}
            {patient.hasAllergy && <Pill tone="orange">{t('mdt.allergy', 'Allergy')}</Pill>}
            {patient.bloodType !== '' && <Pill tone="blue">{patient.bloodType}</Pill>}
        </button>
    );
}

export function PatientsPane() {
    const { selected, select } = useMdtSession();

    const [query, setQuery] = useSessionState('mdt:patients:query', '');
    const [page, setPage]   = useSessionState('mdt:patients:page', 1);
    const [term, setTerm]   = useState(query.trim());

    useEffect(() => {
        const id = window.setTimeout(() => setTerm(query.trim()), 250);
        return () => window.clearTimeout(id);
    }, [query]);

    useEffect(() => { setPage(1); }, [term, setPage]);

    const { data, loading } = useAsyncData(() => mdtPatientsSearch(term, page), [term, page]);
    const rows     = data?.rows ?? [];
    const total    = data?.total ?? 0;
    const pageSize = data?.pageSize ?? 25;
    const short    = term.length < MIN_QUERY;

    const empty = short ? (
        <EmptyState
            center
            icon={Search}
            title={t('mdt.searchAPatient', 'Search for a patient')}
            subtitle={t('mdt.searchAPatientSub', 'Type at least two characters of a name, citizen ID or phone number.')}
        />
    ) : (
        <EmptyState
            center
            icon={Search}
            title={loading ? t('mdt.searching', 'Searching') : t('mdt.noMatches', 'No matches')}
            subtitle={loading ? undefined : t('mdt.noPatientMatch', 'Nobody on record matches that search.')}
        />
    );

    const master = (
        <MdtColumn
            className="flex-1"
            title={t('mdt.patients', 'Patients')}
            count={short ? undefined : total}
            query={query}
            onQuery={setQuery}
            placeholder={t('mdt.searchPatients', 'Name, citizen ID or phone')}
            isEmpty={short || rows.length === 0}
            empty={empty}
            footer={<MdtPager page={data?.page ?? page} pageSize={pageSize} total={total} onPage={setPage} />}
        >
            <div className="flex flex-col gap-0.5">
                {rows.map(row => (
                    <PatientListRow
                        key={row.citizenid}
                        patient={row}
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
            detail={selected ? <PatientRecord key={selected} citizenid={selected} /> : undefined}
            placeholder={
                <EmptyState
                    center
                    icon={HeartPulse}
                    title={t('mdt.pickPatientRecord', 'No patient selected')}
                    subtitle={t('mdt.pickPatientRecordSub', 'Search for a patient and open them to see their medical file and the incidents they appear on.')}
                />
            }
            onCloseDetail={() => select(null)}
        />
    );
}
