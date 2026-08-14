import quipMark from '@/assets/QuipMark.png';

export function QuipMark({ className, color = 'black' }: { className?: string; color?: 'black' | 'white' | 'theme' }) {
    if (color === 'theme') {
        return (
            <span
                aria-hidden
                className={`inline-block bg-ios-blue dark:bg-white ${className ?? ''}`}
                style={{
                    WebkitMaskImage: `url(${quipMark})`,
                    maskImage: `url(${quipMark})`,
                    WebkitMaskPosition: 'center',
                    maskPosition: 'center',
                    WebkitMaskRepeat: 'no-repeat',
                    maskRepeat: 'no-repeat',
                    WebkitMaskSize: 'contain',
                    maskSize: 'contain',
                }}
            />
        );
    }

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
