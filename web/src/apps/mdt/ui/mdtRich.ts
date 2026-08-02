export type MarkId = 'b' | 'i' | 'u' | 's' | 'code';

export interface RichSpan {
    text?: string;
    mark?: MarkId;
    kids?: RichSpan[];
}

export interface RichLine {
    bullet: boolean;
    spans:  RichSpan[];
}

const INLINE: { mark: MarkId; re: RegExp }[] = [
    { mark: 'b',    re: /\*\*([\s\S]+?)\*\*/ },
    { mark: 'u',    re: /__([\s\S]+?)__/ },
    { mark: 's',    re: /~~([\s\S]+?)~~/ },
    { mark: 'i',    re: /\*([\s\S]+?)\*/ },
    { mark: 'code', re: /`([^`\n]+?)`/ },
];

const TAG: Record<MarkId, string> = { b: 'strong', i: 'em', u: 'u', s: 's', code: 'code' };

const MARK_OF_TAG: Record<string, MarkId> = {
    B: 'b', STRONG: 'b',
    I: 'i', EM: 'i',
    U: 'u',
    S: 's', STRIKE: 's', DEL: 's',
    CODE: 'code',
};

const WRAP: Record<MarkId, string> = { b: '**', i: '*', u: '__', s: '~~', code: '`' };

const BLOCK = new Set(['DIV', 'P', 'LI', 'UL', 'OL', 'SECTION', 'ARTICLE', 'BLOCKQUOTE', 'PRE']);

const NBSP = new RegExp(String.fromCharCode(160), 'g');

export function parseInline(text: string): RichSpan[] {
    for (const rule of INLINE) {
        const m = rule.re.exec(text);
        if (!m) continue;
        return [
            ...parseInline(text.slice(0, m.index)),
            { mark: rule.mark, kids: parseInline(m[1]) },
            ...parseInline(text.slice(m.index + m[0].length)),
        ];
    }
    return text ? [{ text }] : [];
}

export function parseLines(md: string): RichLine[] {
    return md.split('\n').map(raw => {
        const line = raw.trimEnd();
        const bullet = /^\s*[-*]\s+(.*)$/.exec(line);
        return bullet
            ? { bullet: true,  spans: parseInline(bullet[1]) }
            : { bullet: false, spans: parseInline(line) };
    });
}

function spansToDom(spans: RichSpan[], into: Node) {
    for (const span of spans) {
        if (span.text !== undefined) {
            into.appendChild(document.createTextNode(span.text));
            continue;
        }
        if (!span.mark) continue;
        const el = document.createElement(TAG[span.mark]);
        spansToDom(span.kids ?? [], el);
        into.appendChild(el);
    }
}

function emptyLine(): HTMLDivElement {
    const div = document.createElement('div');
    div.appendChild(document.createElement('br'));
    return div;
}

export function mdToFragment(md: string): DocumentFragment {
    const frag = document.createDocumentFragment();
    let list: HTMLUListElement | null = null;

    for (const line of parseLines(md)) {
        if (line.bullet) {
            if (!list) {
                list = document.createElement('ul');
                frag.appendChild(list);
            }
            const li = document.createElement('li');
            spansToDom(line.spans, li);
            list.appendChild(li);
            continue;
        }
        list = null;
        if (line.spans.length === 0) {
            frag.appendChild(emptyLine());
            continue;
        }
        const div = document.createElement('div');
        spansToDom(line.spans, div);
        frag.appendChild(div);
    }

    if (!frag.firstChild) frag.appendChild(emptyLine());
    return frag;
}

function inlineNode(node: Node): string {
    if (node.nodeType === Node.TEXT_NODE) return (node.nodeValue ?? '').replace(NBSP, ' ');
    if (node.nodeType !== Node.ELEMENT_NODE) return '';

    const el = node as HTMLElement;
    if (el.tagName === 'BR') return '\n';

    const inner = inlineText(el);
    const mark = MARK_OF_TAG[el.tagName];
    return mark && inner.trim() ? WRAP[mark] + inner + WRAP[mark] : inner;
}

function inlineText(node: Node): string {
    let out = '';
    node.childNodes.forEach(child => { out += inlineNode(child); });
    return out;
}

export function domToMarkdown(root: Node): string {
    const out: string[] = [];

    function emit(text: string, bullet: boolean) {
        for (const line of text.split('\n')) out.push(bullet ? `- ${line}` : line);
    }

    function walk(node: Node, bullet: boolean) {
        const kids = Array.from(node.childNodes);
        const nested = kids.some(k => k.nodeType === Node.ELEMENT_NODE && BLOCK.has((k as HTMLElement).tagName));

        if (!nested) {
            emit(inlineText(node), bullet);
            return;
        }

        let pending = '';
        for (const kid of kids) {
            const el = kid.nodeType === Node.ELEMENT_NODE ? kid as HTMLElement : null;
            if (el && BLOCK.has(el.tagName)) {
                if (pending) { emit(pending, bullet); pending = ''; }
                walk(el, el.tagName === 'LI' ? true : bullet);
                continue;
            }
            pending += inlineNode(kid);
        }
        if (pending) emit(pending, bullet);
    }

    walk(root, false);
    return out.join('\n').replace(/\s+$/, '');
}
