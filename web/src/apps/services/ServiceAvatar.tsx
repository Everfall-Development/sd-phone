export function ServiceAvatar({ color, emoji, iconUrl, size = 50 }: { color: string; emoji: string; iconUrl?: string; size?: number }) {
    return (
        <div
            className="flex shrink-0 items-center justify-center overflow-hidden rounded-full leading-none"
            style={{ background: color, width: size, height: size, fontSize: Math.round(size * 0.52) }}
        >
            {iconUrl ? <img src={iconUrl} alt="" className="h-full w-full object-cover" /> : emoji}
        </div>
    );
}
