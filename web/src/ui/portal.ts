import { createElement, useRef } from 'react';
import { createPortal } from 'react-dom';
import type { ReactNode } from 'react';

import { useInertSiblings } from './useInertSiblings';

function PortalFocusLayer({ children }: { children: ReactNode }) {
    const layerRef = useRef<HTMLDivElement>(null);
    useInertSiblings(layerRef);

    return createElement('div', { ref: layerRef, 'data-motion-app': '1', style: { display: 'contents' } }, children);
}

export function portalToPhoneScreen(node: ReactNode): ReactNode {
    const root = typeof document !== 'undefined'
        ? document.querySelector<HTMLElement>('[data-phone-screen]')
        : null;
    if (!root) return node;
    return createPortal(
        createElement(PortalFocusLayer, null, node),
        root,
    );
}
