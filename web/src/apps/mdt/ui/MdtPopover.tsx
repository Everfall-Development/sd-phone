import { useEffect, useLayoutEffect, useRef, useState } from 'react';

import { ancestorZoom } from '@/lib/zoom';

export interface MdtPopoverAction {
    label:        string;
    onClick:      () => void;
    destructive?: boolean;
    disabled?:    boolean;
}

const GAP = 6;
const EDGE = 8;

export function MdtPopover({ anchor, actions, onClose }: {
    anchor:  HTMLElement | null;
    actions: MdtPopoverAction[];
    onClose: () => void;
}) {
    const hostRef = useRef<HTMLDivElement>(null);
    const [pos, setPos] = useState<{ left: number; top: number } | null>(null);

    useLayoutEffect(() => {
        const host = hostRef.current;
        if (!host || !anchor) return;

        const parent = host.offsetParent as HTMLElement | null;
        const zoom = ancestorZoom(host) || 1;
        const a = anchor.getBoundingClientRect();
        const p = parent?.getBoundingClientRect();

        const boxW = parent ? parent.clientWidth : window.innerWidth;
        const boxH = parent ? parent.clientHeight : window.innerHeight;
        const w = host.offsetWidth;
        const h = host.offsetHeight;

        const anchorLeft = ((a.left - (p?.left ?? 0)) / zoom);
        const anchorRight = ((a.right - (p?.left ?? 0)) / zoom);
        const anchorTop = ((a.top - (p?.top ?? 0)) / zoom);
        const anchorBottom = ((a.bottom - (p?.top ?? 0)) / zoom);

        let left = anchorRight - w;
        if (left < EDGE) left = Math.min(anchorLeft, boxW - w - EDGE);
        left = Math.max(EDGE, Math.min(left, boxW - w - EDGE));

        let top = anchorBottom + GAP;
        if (top + h > boxH - EDGE) top = anchorTop - GAP - h;
        top = Math.max(EDGE, Math.min(top, boxH - h - EDGE));

        setPos({ left, top });
    }, [anchor, actions.length]);

    useEffect(() => {
        function onDown(e: PointerEvent) {
            const host = hostRef.current;
            if (host && e.target instanceof Node && host.contains(e.target)) return;
            onClose();
        }
        function onKey(e: KeyboardEvent) {
            if (e.key === 'Escape') { e.stopPropagation(); onClose(); }
        }
        window.addEventListener('pointerdown', onDown, true);
        window.addEventListener('keydown', onKey, true);
        return () => {
            window.removeEventListener('pointerdown', onDown, true);
            window.removeEventListener('keydown', onKey, true);
        };
    }, [onClose]);

    return (
        <div
            ref={hostRef}
            className="absolute z-20 min-w-[188px] overflow-hidden rounded-[13px] bg-white/95 shadow-[0_8px_30px_rgba(0,0,0,0.18)] ring-1 ring-black/[0.08] dark:bg-elevated/95 dark:ring-white/[0.10]"
            style={{
                left:       pos?.left ?? 0,
                top:        pos?.top ?? 0,
                opacity:    pos ? 1 : 0,
                transformOrigin: 'top right',
                animation:  pos ? 'ios-alert-in 0.16s cubic-bezier(0.32,0.72,0,1)' : undefined,
            }}
        >
            {actions.map((a, i) => (
                <button
                    key={a.label}
                    type="button"
                    disabled={a.disabled}
                    onClick={() => { if (!a.disabled) { onClose(); a.onClick(); } }}
                    className={`block w-full px-4 py-[11px] text-left text-[17px] ${
                        i > 0 ? 'border-t border-black/[0.08] dark:border-white/[0.10]' : ''
                    } ${
                        a.disabled
                            ? 'text-black/30 dark:text-white/30'
                            : `active:bg-black/[0.06] dark:active:bg-white/[0.08] ${a.destructive ? 'text-ios-red' : 'text-ios-blue'}`
                    }`}
                >
                    {a.label}
                </button>
            ))}
        </div>
    );
}
