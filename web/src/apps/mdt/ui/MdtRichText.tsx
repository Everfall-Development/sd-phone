import type { ReactNode } from 'react';

import { parseLines, type MarkId, type RichSpan } from './mdtRich';

const WRAPPER: Record<MarkId, (kids: ReactNode[], key: string) => ReactNode> = {
    b:    (k, key) => <strong key={key} className="font-semibold">{k}</strong>,
    i:    (k, key) => <em key={key}>{k}</em>,
    u:    (k, key) => <u key={key}>{k}</u>,
    s:    (k, key) => <s key={key} className="opacity-70">{k}</s>,
    code: (k, key) => (
        <code key={key} className="rounded-[4px] bg-black/[0.07] px-1 py-[1px] font-mono text-[0.92em] dark:bg-white/[0.10]">
            {k}
        </code>
    ),
};

function render(spans: RichSpan[], key: string): ReactNode[] {
    return spans.map((span, i) => {
        if (span.text !== undefined) return span.text;
        if (!span.mark) return null;
        return WRAPPER[span.mark](render(span.kids ?? [], `${key}.${i}`), `${key}.${i}`);
    });
}

export function MdtRichText({ text, className = '' }: { text: string; className?: string }) {
    const lines = parseLines(text);
    const blocks: ReactNode[] = [];
    let bullets: { spans: RichSpan[]; at: number }[] = [];

    function flush(at: number) {
        if (bullets.length === 0) return;
        blocks.push(
            <ul key={`u${at}`} className="my-1 list-disc pl-5">
                {bullets.map(b => <li key={b.at}>{render(b.spans, `u${b.at}`)}</li>)}
            </ul>,
        );
        bullets = [];
    }

    lines.forEach((line, i) => {
        if (line.bullet) { bullets.push({ spans: line.spans, at: i }); return; }
        flush(i);
        if (line.spans.length === 0) { blocks.push(<div key={`s${i}`} className="h-3" />); return; }
        blocks.push(<p key={`p${i}`}>{render(line.spans, `p${i}`)}</p>);
    });
    flush(lines.length);

    return <div className={`whitespace-pre-wrap break-words ${className}`}>{blocks}</div>;
}
