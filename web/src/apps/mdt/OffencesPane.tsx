import { useEffect, useMemo, useState } from 'react';
import { Scale } from 'lucide-react';

import { t } from '@/i18n';
import { formatMoney } from '@/lib/money';
import { useAsyncData } from '@/hooks/useAsyncData';
import { useSessionState } from '@/hooks/useSessionState';
import { AlertDialog } from '@/ui/AlertDialog';
import { EmptyState } from '@/ui/EmptyState';
import { Pill } from '@/ui/Pill';
import { Scroller } from '@/ui/Scroller';

import { classLabel, sentenceLabel } from './ChargePicker';
import { CHARGE_CLASSES, type ChargeClass, type Offence } from './data';
import { mdtDeleteOffence, mdtOffences, mdtSaveOffence } from './mdtApi';
import { useMdtSession, useViewEnter } from './useMdtSession';
import { mdtPanePad, mdtRowHover, mdtRowMeta, mdtSectionHeader, STATUS_TONE } from './mdtTheme';
import { MdtButton } from './ui/MdtButton';
import { MdtCard } from './ui/MdtCard';
import { MdtColumn } from './ui/MdtColumn';
import { MdtField } from './ui/MdtField';
import { MdtMaster } from './ui/MdtMaster';

interface Draft {
    code:        string;
    label:       string;
    class:       ChargeClass;
    months:      string;
    fine:        string;
    description: string;
}

function draftOf(offence: Offence | null): Draft {
    if (!offence) {
        return { code: '', label: '', class: 'misdemeanor', months: '0', fine: '0', description: '' };
    }
    return {
        code:        offence.code,
        label:       offence.label,
        class:       offence.class,
        months:      String(offence.months),
        fine:        String(offence.fine),
        description: offence.description,
    };
}

export function OffencesPane() {
    const { can, refresh } = useMdtSession();
    const manage = can('offences.manage');

    const [query, setQuery] = useSessionState('mdt:offences:query', '');
    const [code, setCode] = useSessionState<string | null>('mdt:offences:code', null);
    const [creating, setCreating] = useState(false);

    const { data, loading, refetch } = useAsyncData(mdtOffences, []);
    const offences = useMemo(() => data ?? [], [data]);

    const groups = useMemo(() => {
        const needle = query.trim().toLowerCase();
        const hits = needle.length === 0
            ? offences
            : offences.filter(o =>
                o.code.toLowerCase().includes(needle)
                || o.label.toLowerCase().includes(needle)
                || o.description.toLowerCase().includes(needle));
        return CHARGE_CLASSES
            .map(cls => ({ cls, rows: hits.filter(o => o.class === cls) }))
            .filter(group => group.rows.length > 0);
    }, [offences, query]);

    const selected = useMemo(() => offences.find(o => o.code === code) ?? null, [offences, code]);

    function reload() {
        refetch();
        refresh();
    }

    const empty = (
        <EmptyState
            center
            icon={Scale}
            title={loading ? t('mdt.loadingCode', 'Loading the penal code') : t('mdt.noOffences', 'No offences')}
            subtitle={loading
                ? undefined
                : query.trim()
                    ? t('mdt.noOffencesSub', 'Nothing in the penal code matches that search.')
                    : t('mdt.emptyCode', 'The penal code has not been seeded on this server yet.')}
        />
    );

    const master = (
        <MdtColumn
            className="flex-1"
            title={t('mdt.offences', 'Offences')}
            count={offences.length}
            query={query}
            onQuery={setQuery}
            placeholder={t('mdt.searchOffencesShort', 'Code, label or wording')}
            action={manage ? (
                <MdtButton size="sm" onClick={() => { setCreating(true); setCode(null); }}>
                    {t('mdt.newOffence', 'New')}
                </MdtButton>
            ) : undefined}
            isEmpty={groups.length === 0}
            empty={empty}
        >
            {groups.map(group => (
                <div key={group.cls}>
                    <div className="sticky top-0 z-10 bg-[#d4d4d4]/95 px-4 py-1 backdrop-blur-sm dark:bg-base/95">
                        <span className={mdtSectionHeader}>{classLabel(group.cls)}</span>
                    </div>
                    <div className="flex flex-col gap-0.5 px-1">
                        {group.rows.map(offence => (
                            <button
                                key={offence.code}
                                type="button"
                                onClick={() => { setCreating(false); setCode(offence.code); }}
                                className={`flex w-full items-center gap-3 rounded-[10px] px-3 py-2 text-left ${
                                    offence.code === code && !creating ? 'bg-ios-blue/10' : mdtRowHover
                                }`}
                            >
                                <span className="w-[64px] shrink-0 text-[12.5px] font-bold uppercase tabular-nums tracking-wide text-ios-gray">
                                    {offence.code}
                                </span>
                                <span className="min-w-0 flex-1 truncate text-[14.5px] text-black dark:text-white">
                                    {offence.label}
                                </span>
                                <span className={`shrink-0 tabular-nums ${mdtRowMeta}`}>
                                    {offence.months > 0 ? `${offence.months}m` : '-'}
                                    {' · '}
                                    {formatMoney(offence.fine, { whole: true })}
                                </span>
                            </button>
                        ))}
                    </div>
                </div>
            ))}
        </MdtColumn>
    );

    return (
        <MdtMaster
            master={master}
            hasDetail={creating || selected !== null}
            detail={creating || selected ? (
                <OffenceDetail
                    key={creating ? 'new' : selected?.code}
                    offence={creating ? null : selected}
                    manage={manage}
                    onSaved={saved => { setCreating(false); setCode(saved.code); reload(); }}
                    onDeleted={() => { setCreating(false); setCode(null); reload(); }}
                    onCancel={() => { setCreating(false); setCode(null); }}
                />
            ) : undefined}
            placeholder={
                <EmptyState
                    center
                    icon={Scale}
                    title={t('mdt.pickOffence', 'No offence selected')}
                    subtitle={t('mdt.pickOffenceSub', 'Open a code to read what it carries in jail time and fines.')}
                />
            }
            onCloseDetail={() => { setCreating(false); setCode(null); }}
        />
    );
}

function OffenceDetail({ offence, manage, onSaved, onDeleted, onCancel }: {
    offence:   Offence | null;
    manage:    boolean;
    onSaved:   (offence: Offence) => void;
    onDeleted: () => void;
    onCancel:  () => void;
}) {
    const [editing, setEditing] = useState(offence === null);
    const [draft, setDraft] = useState<Draft>(() => draftOf(offence));
    const [error, setError] = useState('');
    const [saving, setSaving] = useState(false);
    const [confirm, setConfirm] = useState(false);

    const enter = useViewEnter(editing ? 'edit' : offence ? 'read' : null);

    useEffect(() => {
        setDraft(draftOf(offence));
        setEditing(offence === null);
        setError('');
    }, [offence]);

    async function save() {
        if (saving) return;
        if (!draft.code.trim() || !draft.label.trim()) {
            setError(t('mdt.offenceNeedsCode', 'A code and a label are both required.'));
            return;
        }
        setSaving(true);
        const saved = await mdtSaveOffence({
            code:        draft.code.trim(),
            label:       draft.label.trim(),
            class:       draft.class,
            months:      Number(draft.months) || 0,
            fine:        Number(draft.fine) || 0,
            description: draft.description.trim(),
        });
        setSaving(false);
        if (!saved) {
            setError(t('mdt.saveFailed', 'That could not be saved.'));
            return;
        }
        setEditing(false);
        onSaved(saved);
    }

    async function remove() {
        setConfirm(false);
        if (!offence) return;
        const ok = await mdtDeleteOffence(offence.code);
        if (ok) onDeleted();
        else setError(t('mdt.deleteFailed', 'That could not be deleted.'));
    }

    if (editing) {
        return (
            <Scroller key="edit" className={`h-full ${mdtPanePad} ${enter}`}>
                <h1 className="text-[26px] font-bold tracking-ios-display text-black dark:text-white">
                    {offence ? t('mdt.editOffence', 'Edit offence') : t('mdt.newOffenceTitle', 'New offence')}
                </h1>

                <div className="mt-5 grid gap-4" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))' }}>
                    <MdtField
                        label={t('mdt.code', 'Code')}
                        value={draft.code}
                        onChange={v => setDraft(d => ({ ...d, code: v }))}
                        placeholder="PC 101"
                        maxLength={16}
                        disabled={offence !== null}
                        hint={offence ? t('mdt.codeLocked', 'A code cannot be renamed once it is in use.') : undefined}
                    />
                    <MdtField
                        label={t('mdt.label', 'Label')}
                        value={draft.label}
                        onChange={v => setDraft(d => ({ ...d, label: v }))}
                        placeholder={t('mdt.offenceLabelHint', 'Grand Theft Auto')}
                        maxLength={120}
                    />
                    <MdtField
                        label={t('mdt.class', 'Class')}
                        value={draft.class}
                        onChange={v => setDraft(d => ({ ...d, class: v as ChargeClass }))}
                        options={CHARGE_CLASSES.map(cls => ({ value: cls, label: classLabel(cls) }))}
                    />
                    <MdtField
                        label={t('mdt.months', 'Jail months')}
                        value={draft.months}
                        onChange={v => setDraft(d => ({ ...d, months: v.replace(/\D/g, '').slice(0, 3) }))}
                        inputMode="numeric"
                        placeholder="0"
                    />
                    <MdtField
                        label={t('mdt.fine', 'Fine')}
                        value={draft.fine}
                        onChange={v => setDraft(d => ({ ...d, fine: v.replace(/\D/g, '').slice(0, 7) }))}
                        inputMode="numeric"
                        placeholder="0"
                    />
                </div>

                <div className="mt-4">
                    <MdtField
                        multiline
                        rows={4}
                        label={t('mdt.description', 'Description')}
                        value={draft.description}
                        onChange={v => setDraft(d => ({ ...d, description: v }))}
                        maxLength={255}
                        placeholder={t('mdt.offenceDescriptionHint', 'What conduct this code actually covers.')}
                    />
                </div>

                {error && <div className="mt-4 text-[14px] text-ios-red">{error}</div>}

                <div className="mt-5 flex items-center gap-3 pb-6">
                    <MdtButton variant="filled" disabled={saving} onClick={() => void save()}>
                        {saving ? t('mdt.saving', 'Saving') : t('common.save', 'Save')}
                    </MdtButton>
                    <MdtButton
                        variant="text"
                        onClick={() => {
                            if (!offence) { onCancel(); return; }
                            setDraft(draftOf(offence));
                            setEditing(false);
                        }}
                    >
                        {t('common.cancel', 'Cancel')}
                    </MdtButton>
                </div>
            </Scroller>
        );
    }

    if (!offence) return null;

    return (
        <Scroller key="read" className={`h-full ${mdtPanePad} ${enter}`}>
            <div className="flex flex-wrap items-center gap-3">
                <span className="shrink-0 text-[13px] font-bold uppercase tabular-nums tracking-wide text-ios-gray">
                    {offence.code}
                </span>
                <h1 className="min-w-0 flex-1 text-[26px] font-bold leading-tight tracking-ios-display text-black dark:text-white">
                    {offence.label}
                </h1>
                <Pill tone={STATUS_TONE[offence.class] ?? 'blue'}>{classLabel(offence.class)}</Pill>
            </div>

            <MdtCard className="mt-5 overflow-hidden">
                <div className="grid" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))' }}>
                    <div className="p-4">
                        <div className={mdtSectionHeader}>{t('mdt.jailTime', 'Jail time')}</div>
                        <div className="mt-1 text-[20px] font-semibold tabular-nums text-black dark:text-white">
                            {sentenceLabel(offence.months)}
                        </div>
                    </div>
                    <div className="p-4">
                        <div className={mdtSectionHeader}>{t('mdt.fine', 'Fine')}</div>
                        <div className="mt-1 text-[20px] font-semibold tabular-nums text-black dark:text-white">
                            {formatMoney(offence.fine, { whole: true })}
                        </div>
                    </div>
                </div>
            </MdtCard>

            <MdtCard className="mt-4 p-4">
                <div className={mdtSectionHeader}>{t('mdt.description', 'Description')}</div>
                <p className="mt-1 whitespace-pre-wrap text-[15px] leading-relaxed text-black dark:text-white">
                    {offence.description || t('mdt.noDescription', 'No description on file for this code.')}
                </p>
            </MdtCard>

            {error && <div className="mt-4 text-[14px] text-ios-red">{error}</div>}

            {manage && (
                <div className="mt-5 flex items-center gap-3 pb-6">
                    <MdtButton variant="filled" onClick={() => setEditing(true)}>
                        {t('common.edit', 'Edit')}
                    </MdtButton>
                    <MdtButton variant="destructive" onClick={() => setConfirm(true)}>
                        {t('common.delete', 'Delete')}
                    </MdtButton>
                </div>
            )}

            {confirm && (
                <AlertDialog
                    destructive
                    title={t('mdt.deleteOffence', 'Delete this offence?')}
                    message={t('mdt.deleteOffenceSub', 'Charges already filed keep the figures they were stamped with.')}
                    confirmLabel={t('common.delete', 'Delete')}
                    onCancel={() => setConfirm(false)}
                    onConfirm={() => void remove()}
                />
            )}
        </Scroller>
    );
}
