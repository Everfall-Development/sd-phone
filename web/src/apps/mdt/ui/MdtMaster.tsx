import { useEffect, useRef, useState, type ReactNode } from 'react';

import { SlideOver } from '@/ui/SlideOver';
import { mdtBackdrop, mdtRuleY } from '../mdtTheme';

const DETAIL_MIN = 420;

interface MdtMasterProps {
    master:         ReactNode;
    detail?:        ReactNode;
    placeholder?:   ReactNode;
    hasDetail?:     boolean;
    masterWidth?:   number;
    onCloseDetail?: () => void;
    onBack?:        () => void;
    className?:     string;
}

export function MdtMaster(props: MdtMasterProps) {
    const {
        master, detail, placeholder, hasDetail, masterWidth = 372, onCloseDetail, onBack, className = '',
    } = props;

    const hostRef = useRef<HTMLDivElement>(null);
    const [narrow, setNarrow] = useState(false);

    useEffect(() => {
        const host = hostRef.current;
        if (!host) return;
        const measure = () => setNarrow(host.clientWidth < masterWidth + DETAIL_MIN);
        measure();
        if (typeof ResizeObserver === 'undefined') return;
        const ro = new ResizeObserver(measure);
        ro.observe(host);
        return () => ro.disconnect();
    }, [masterWidth]);

    const open = hasDetail ?? ('onBack' in props ? !!onBack : detail != null);
    const close = onCloseDetail ?? onBack;

    if (narrow) {
        return (
            <div ref={hostRef} className={`relative flex min-h-0 min-w-0 flex-1 ${className}`}>
                <div className="flex min-h-0 min-w-0 flex-1 flex-col">{master}</div>
                {open && detail && (
                    <SlideOver onClose={() => close?.()} direction="x" className={mdtBackdrop}>
                        {() => <div className="flex h-full min-h-0 flex-col">{detail}</div>}
                    </SlideOver>
                )}
            </div>
        );
    }

    return (
        <div ref={hostRef} className={`flex min-h-0 min-w-0 flex-1 ${className}`}>
            <div className="flex min-h-0 shrink-0 flex-col" style={{ width: masterWidth }}>
                {master}
            </div>
            <div className={mdtRuleY} />
            <div className="relative flex min-h-0 min-w-0 flex-1 flex-col">
                {detail ?? placeholder}
            </div>
        </div>
    );
}
