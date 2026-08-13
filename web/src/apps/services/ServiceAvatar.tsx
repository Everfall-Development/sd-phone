import { useState } from 'react';

export function ServiceAvatar({ color, emoji, iconUrl, size = 50 }: { color: string; emoji: string; iconUrl?: string; size?: number }) {
    const [failedUrl, setFailedUrl] = useState<string | null>(null);
    const imageUrl = iconUrl && failedUrl !== iconUrl ? iconUrl : null;

    return (
        <div
            className="flex shrink-0 items-center justify-center overflow-hidden rounded-full leading-none"
            style={{ background: color, width: size, height: size, fontSize: Math.round(size * 0.52) }}
        >
            {imageUrl
                ? <img src={imageUrl} alt="" className="h-full w-full object-contain p-[8%]" onError={() => setFailedUrl(imageUrl)} />
                : emoji}
        </div>
    );
}
