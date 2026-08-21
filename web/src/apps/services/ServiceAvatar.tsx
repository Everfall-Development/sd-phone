import { useState } from 'react';

export function ServiceAvatar({ emoji, iconUrl, size = 50 }: { emoji: string; iconUrl?: string; size?: number }) {
    const [failedUrl, setFailedUrl] = useState<string | null>(null);
    const [loadedUrl, setLoadedUrl] = useState<string | null>(null);
    const imageUrl = iconUrl && failedUrl !== iconUrl ? iconUrl : null;
    const imageLoaded = imageUrl !== null && loadedUrl === imageUrl;

    return (
        <div
            aria-hidden="true"
            className="relative flex shrink-0 items-center justify-center overflow-hidden bg-transparent leading-none"
            style={{ width: size, height: size, fontSize: Math.round(size * 0.52) }}
        >
            {!imageLoaded && emoji}
            {imageUrl && (
                <img
                    src={imageUrl}
                    alt=""
                    draggable={false}
                    className={`absolute inset-0 h-full w-full object-contain p-[8%] ${imageLoaded ? 'opacity-100' : 'opacity-0'}`}
                    onLoad={() => setLoadedUrl(imageUrl)}
                    onError={() => setFailedUrl(imageUrl)}
                />
            )}
        </div>
    );
}
