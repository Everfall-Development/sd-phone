import kaleidoIcon from '@/assets/Kaleido.jpg';

export function KaleidoMark({ className }: { className?: string }) {
    return (
        <img
            src={kaleidoIcon}
            alt=""
            aria-hidden
            draggable={false}
            className={`rounded-[22%] object-cover ${className ?? ''}`}
        />
    );
}
