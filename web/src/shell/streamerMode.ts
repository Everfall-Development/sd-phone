export type StreamerHideKey = 'balance' | 'transactions' | 'card' | 'investments' | 'number' | 'previews';

export const STREAMER_HIDE_KEYS: readonly StreamerHideKey[] = [
    'balance',
    'transactions',
    'card',
    'investments',
    'number',
    'previews',
];

export type StreamerHide = Record<StreamerHideKey, boolean>;

export const STREAMER_HIDE_ALL: StreamerHide = {
    balance:      true,
    transactions: true,
    card:         true,
    investments:  true,
    number:       true,
    previews:     true,
};

export const HIDDEN_TEXT = '••••';

function isRecord(value: unknown): value is Record<string, unknown> {
    return value !== null && typeof value === 'object';
}

export function normalizeStreamerHide(raw: unknown): StreamerHide {
    const out = { ...STREAMER_HIDE_ALL };
    if (isRecord(raw)) {
        for (const key of STREAMER_HIDE_KEYS) {
            const v = raw[key];
            if (typeof v === 'boolean') out[key] = v;
        }
    }
    return out;
}
