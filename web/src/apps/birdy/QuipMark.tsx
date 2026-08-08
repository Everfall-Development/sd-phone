import quipMark from '@/assets/QuipMark.png';

export function QuipMark({ className, color = 'black' }: { className?: string; color?: 'black' | 'white' }) {
    return (
        <img
            src={quipMark}
            alt=""
            aria-hidden
            draggable={false}
            className={`object-contain ${color === 'black' ? 'invert' : ''} ${className ?? ''}`}
        />
    );
}
