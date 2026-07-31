import { t } from '@/i18n';
import { mdtRuleX } from '../mdtTheme';
import { MdtButton } from './MdtButton';

export function MdtPager({ page, pageSize, total, onPage }: {
    page:     number;
    pageSize: number;
    total:    number;
    onPage:   (page: number) => void;
}) {
    if (total <= pageSize) return null;

    const first = total === 0 ? 0 : (page - 1) * pageSize + 1;
    const last = Math.min(page * pageSize, total);
    const lastPage = Math.max(1, Math.ceil(total / pageSize));

    return (
        <div className="shrink-0">
            <div className={mdtRuleX} />
            <div className="flex items-center gap-2 px-4 py-2">
                <span className="min-w-0 truncate text-[12.5px] font-medium tabular-nums text-ios-gray">
                    {t('mdt.showingRange', 'Showing {first}-{last} of {total}', { first, last, total })}
                </span>
                <span className="flex-1" />
                <MdtButton size="sm" variant="text" disabled={page <= 1} onClick={() => onPage(page - 1)}>
                    {t('mdt.previous', 'Previous')}
                </MdtButton>
                <MdtButton size="sm" variant="text" disabled={page >= lastPage} onClick={() => onPage(page + 1)}>
                    {t('mdt.next', 'Next')}
                </MdtButton>
            </div>
        </div>
    );
}
