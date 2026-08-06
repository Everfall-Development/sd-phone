import { BadgeCheck } from 'lucide-react';

export interface FormalDocumentField {
    label: string;
    value: string;
}

export interface FormalDocumentSection {
    title: string;
    body?: string;
    fields?: FormalDocumentField[];
}

export interface FormalDocumentSignature {
    label: string;
    signerName: string;
    signerCitizenid: string;
    signedAt: string;
    signatureImage?: string;
}

export interface FormalDocumentPayload {
    schemaVersion: 1;
    issuer: string;
    title: string;
    subtitle?: string;
    reference?: string;
    status?: string;
    introduction?: string;
    sections: FormalDocumentSection[];
    signatures?: FormalDocumentSignature[];
    footer?: string;
}

function isString(value: unknown): value is string {
    return typeof value === 'string';
}

function isFormalDocumentField(value: unknown): value is FormalDocumentField {
    if (!value || typeof value !== 'object') return false;
    const field = value as Partial<FormalDocumentField>;
    return isString(field.label) && isString(field.value);
}

function isFormalDocumentSection(value: unknown): value is FormalDocumentSection {
    if (!value || typeof value !== 'object') return false;
    const section = value as Partial<FormalDocumentSection>;
    return isString(section.title)
        && (section.body === undefined || isString(section.body))
        && (section.fields === undefined
            || Array.isArray(section.fields) && section.fields.every(isFormalDocumentField));
}

function isFormalDocumentSignature(value: unknown): value is FormalDocumentSignature {
    if (!value || typeof value !== 'object') return false;
    const signature = value as Partial<FormalDocumentSignature>;
    return isString(signature.label)
        && isString(signature.signerName)
        && isString(signature.signerCitizenid)
        && isString(signature.signedAt)
        && (signature.signatureImage === undefined || isString(signature.signatureImage));
}

function parseFormalDocument(content: string): FormalDocumentPayload | null {
    try {
        const value: unknown = JSON.parse(content);
        if (!value || typeof value !== 'object') return null;
        const document = value as Partial<FormalDocumentPayload>;
        if (
            document.schemaVersion !== 1
            || !isString(document.issuer)
            || !isString(document.title)
            || !Array.isArray(document.sections)
            || !document.sections.every(isFormalDocumentSection)
            || document.signatures !== undefined
                && (!Array.isArray(document.signatures)
                    || !document.signatures.every(isFormalDocumentSignature))
        ) return null;
        return document as FormalDocumentPayload;
    } catch {
        return null;
    }
}

function DocumentField({ field }: { field: FormalDocumentField }) {
    return (
        <div className="min-w-0">
            <dt className="text-[8px] font-bold uppercase tracking-[0.12em] text-[#756e62]">
                {field.label}
            </dt>
            <dd className="mt-1 break-words font-serif text-[12px] font-semibold leading-[1.25] text-[#211f1b]">
                {field.value}
            </dd>
        </div>
    );
}

export function FormalDocument({ content }: { content: string }) {
    const document = parseFormalDocument(content);
    if (!document) {
        return (
            <p className="my-4 rounded-[12px] bg-black/[0.06] px-4 py-3 text-[15px] text-ios-gray dark:bg-white/[0.08]">
                This official document could not be displayed.
            </p>
        );
    }

    return (
        <article className="mb-6 mt-4 border border-[#403c34] bg-[#f3efe4] px-4 py-6 text-[#211f1b] shadow-[0_8px_24px_rgba(0,0,0,0.18)]">
            <header className="border-b-2 border-[#403c34] pb-5 text-center">
                <p className="font-serif text-[9px] font-bold uppercase tracking-[0.28em]">
                    {document.issuer}
                </p>
                <h1 className="mt-3 font-serif text-[20px] font-bold uppercase leading-tight tracking-[0.05em]">
                    {document.title}
                </h1>
                {document.subtitle && <p className="mt-3 font-serif text-[12px]">{document.subtitle}</p>}
                {document.reference && (
                    <p className="mt-2 break-all font-mono text-[8px] uppercase tracking-wide text-[#756e62]">
                        {document.reference}
                    </p>
                )}
                {document.status && (
                    <span className="mt-3 inline-flex items-center gap-1 rounded-full border border-[#756e62]/40 bg-white/35 px-2.5 py-1 text-[8px] font-bold uppercase tracking-wider">
                        <BadgeCheck className="h-3 w-3" strokeWidth={2.2} />
                        {document.status}
                    </span>
                )}
            </header>

            {document.introduction && (
                <p className="mt-5 whitespace-pre-wrap font-serif text-[11px] leading-[1.6]">
                    {document.introduction}
                </p>
            )}

            {document.sections.map((section, sectionIndex) => (
                <section key={`${section.title}-${sectionIndex}`} className="mt-6">
                    <h2 className="border-b border-[#8a8274] pb-1.5 font-serif text-[10px] font-bold uppercase tracking-[0.14em]">
                        {section.title}
                    </h2>
                    {section.body && (
                        <p className="mt-3 whitespace-pre-wrap font-serif text-[11px] leading-[1.6]">
                            {section.body}
                        </p>
                    )}
                    {section.fields && section.fields.length > 0 && (
                        <dl className="mt-4 grid grid-cols-2 gap-x-4 gap-y-4">
                            {section.fields.map((field, fieldIndex) => (
                                <DocumentField key={`${field.label}-${fieldIndex}`} field={field} />
                            ))}
                        </dl>
                    )}
                </section>
            ))}

            {document.signatures && document.signatures.length > 0 && (
                <section className="mt-7">
                    <h2 className="border-b border-[#8a8274] pb-1.5 font-serif text-[10px] font-bold uppercase tracking-[0.14em]">
                        Execution
                    </h2>
                    <div className="mt-4 flex flex-col gap-5">
                        {document.signatures.map((signature, signatureIndex) => (
                            <div key={`${signature.label}-${signatureIndex}`} className="border-b border-[#8a8274] pb-3">
                                {signature.signatureImage ? (
                                    <img
                                        src={signature.signatureImage}
                                        alt={`${signature.label} signature`}
                                        className="h-[72px] max-w-full object-contain object-left mix-blend-multiply"
                                        draggable={false}
                                    />
                                ) : <div className="h-10" />}
                                <p className="font-serif text-[11px] font-bold">{signature.label}</p>
                                <p className="mt-1 text-[9px] text-[#756e62]">
                                    {signature.signerName} ({signature.signerCitizenid})
                                </p>
                                <p className="mt-1 text-[8px] text-[#756e62]">Signed {signature.signedAt}</p>
                            </div>
                        ))}
                    </div>
                </section>
            )}

            {document.footer && (
                <footer className="mt-7 border-t-2 border-[#403c34] pt-3 font-serif text-[8px] leading-[1.6] text-[#756e62]">
                    {document.footer}
                </footer>
            )}
        </article>
    );
}
