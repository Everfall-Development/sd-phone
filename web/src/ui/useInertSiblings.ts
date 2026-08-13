import { useLayoutEffect } from 'react';
import type { RefObject } from 'react';

interface InertRecord {
    count: number;
    inert: boolean;
    ariaHidden: string | null;
}

const inertRecords = new Map<HTMLElement, InertRecord>();

function acquireInert(element: HTMLElement) {
    const existing = inertRecords.get(element);
    if (existing) {
        existing.count += 1;
    } else {
        inertRecords.set(element, {
            count: 1,
            inert: element.inert,
            ariaHidden: element.getAttribute('aria-hidden'),
        });
    }

    element.inert = true;
    element.setAttribute('aria-hidden', 'true');
}

function releaseInert(element: HTMLElement) {
    const record = inertRecords.get(element);
    if (!record) return;

    record.count -= 1;
    if (record.count > 0) return;

    element.inert = record.inert;
    if (record.ariaHidden === null) element.removeAttribute('aria-hidden');
    else element.setAttribute('aria-hidden', record.ariaHidden);
    inertRecords.delete(element);
}

export function useInertSiblings(layerRef: RefObject<HTMLElement | null>, active = true) {
    useLayoutEffect(() => {
        if (!active) return;

        const layer = layerRef.current;
        const parent = layer?.parentElement;
        if (!layer || !parent) return;

        const siblings = new Set<HTMLElement>();

        function trackSibling(sibling: Element) {
            if (sibling === layer || !(sibling instanceof HTMLElement)) return;
            if (siblings.has(sibling)) return;
            acquireInert(sibling);
            siblings.add(sibling);
        }

        function releaseSibling(sibling: Node) {
            if (!(sibling instanceof HTMLElement) || !siblings.has(sibling)) return;
            if (sibling.parentElement === parent) return;
            releaseInert(sibling);
            siblings.delete(sibling);
        }

        for (const sibling of parent.children) trackSibling(sibling);

        const observer = new MutationObserver(records => {
            for (const record of records) {
                for (const sibling of record.removedNodes) releaseSibling(sibling);
                for (const sibling of record.addedNodes) {
                    if (sibling instanceof Element) trackSibling(sibling);
                }
            }
        });
        observer.observe(parent, { childList: true });

        return () => {
            observer.disconnect();
            for (const sibling of siblings) releaseInert(sibling);
        };
    }, [active, layerRef]);
}
