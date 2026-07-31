import { t } from '@/i18n';

export interface FaceAnchor {
    u:    number;
    v:    number;
    fx:   number;
    fy:   number;
    roll: number;
}

export interface CameraMask {
    id:   string;
    draw: (ctx: CanvasRenderingContext2D, s: number) => void;
}

function ear(ctx: CanvasRenderingContext2D, s: number, dir: 1 | -1, outer: string, inner: string) {
    ctx.save();
    ctx.translate(dir * 0.62 * s, -0.72 * s);
    ctx.rotate(dir * 0.36);
    ctx.fillStyle = outer;
    ctx.beginPath();
    ctx.ellipse(0, 0, 0.30 * s, 0.52 * s, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = inner;
    ctx.beginPath();
    ctx.ellipse(0, 0.04 * s, 0.16 * s, 0.32 * s, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
}

function snout(ctx: CanvasRenderingContext2D, s: number, fill: string) {
    ctx.fillStyle = fill;
    ctx.beginPath();
    ctx.ellipse(0, 0.16 * s, 0.20 * s, 0.14 * s, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#1b1b1f';
    ctx.beginPath();
    ctx.ellipse(0, 0.11 * s, 0.10 * s, 0.075 * s, 0, 0, Math.PI * 2);
    ctx.fill();
}

function tongue(ctx: CanvasRenderingContext2D, s: number) {
    ctx.fillStyle = '#F0567F';
    ctx.beginPath();
    ctx.moveTo(-0.11 * s, 0.26 * s);
    ctx.quadraticCurveTo(0, 0.24 * s, 0.11 * s, 0.26 * s);
    ctx.quadraticCurveTo(0.13 * s, 0.56 * s, 0, 0.58 * s);
    ctx.quadraticCurveTo(-0.13 * s, 0.56 * s, -0.11 * s, 0.26 * s);
    ctx.fill();
    ctx.strokeStyle = 'rgba(0,0,0,0.18)';
    ctx.lineWidth = 0.012 * s;
    ctx.beginPath();
    ctx.moveTo(0, 0.34 * s);
    ctx.lineTo(0, 0.54 * s);
    ctx.stroke();
}

function glasses(ctx: CanvasRenderingContext2D, s: number, lens: string, frame: string) {
    ctx.strokeStyle = frame;
    ctx.lineWidth = 0.045 * s;
    ctx.fillStyle = lens;
    for (const dir of [-1, 1] as const) {
        ctx.beginPath();
        ctx.ellipse(dir * 0.26 * s, -0.06 * s, 0.21 * s, 0.16 * s, 0, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();
    }
    ctx.beginPath();
    ctx.moveTo(-0.05 * s, -0.06 * s);
    ctx.lineTo(0.05 * s, -0.06 * s);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(-0.47 * s, -0.09 * s);
    ctx.lineTo(-0.62 * s, -0.16 * s);
    ctx.moveTo(0.47 * s, -0.09 * s);
    ctx.lineTo(0.62 * s, -0.16 * s);
    ctx.stroke();
}

function petal(ctx: CanvasRenderingContext2D, s: number, angle: number, r: number, fill: string) {
    ctx.save();
    ctx.rotate(angle);
    ctx.fillStyle = fill;
    ctx.beginPath();
    ctx.ellipse(0, -r, 0.11 * s, 0.16 * s, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
}

export const CAMERA_MASKS: readonly CameraMask[] = [
    {
        id: 'dog',
        draw: (ctx, s) => {
            ear(ctx, s, -1, '#6B4A2F', '#C99A6B');
            ear(ctx, s,  1, '#6B4A2F', '#C99A6B');
            snout(ctx, s, '#C99A6B');
            tongue(ctx, s);
        },
    },
    {
        id: 'bunny',
        draw: (ctx, s) => {
            for (const dir of [-1, 1] as const) {
                ctx.save();
                ctx.translate(dir * 0.30 * s, -0.95 * s);
                ctx.rotate(dir * 0.20);
                ctx.fillStyle = '#F5F1EC';
                ctx.beginPath();
                ctx.ellipse(0, 0, 0.16 * s, 0.62 * s, 0, 0, Math.PI * 2);
                ctx.fill();
                ctx.fillStyle = '#F2A6C0';
                ctx.beginPath();
                ctx.ellipse(0, 0.03 * s, 0.075 * s, 0.44 * s, 0, 0, Math.PI * 2);
                ctx.fill();
                ctx.restore();
            }
            snout(ctx, s, '#F5F1EC');
        },
    },
    {
        id: 'cat',
        draw: (ctx, s) => {
            for (const dir of [-1, 1] as const) {
                ctx.save();
                ctx.translate(dir * 0.52 * s, -0.78 * s);
                ctx.fillStyle = '#3A3238';
                ctx.beginPath();
                ctx.moveTo(-0.24 * s, 0.30 * s);
                ctx.lineTo(0, -0.34 * s);
                ctx.lineTo(0.24 * s, 0.30 * s);
                ctx.closePath();
                ctx.fill();
                ctx.fillStyle = '#F2A6C0';
                ctx.beginPath();
                ctx.moveTo(-0.13 * s, 0.22 * s);
                ctx.lineTo(0, -0.16 * s);
                ctx.lineTo(0.13 * s, 0.22 * s);
                ctx.closePath();
                ctx.fill();
                ctx.restore();
            }
            snout(ctx, s, '#F2A6C0');
            ctx.strokeStyle = 'rgba(255,255,255,0.85)';
            ctx.lineWidth = 0.016 * s;
            for (const dir of [-1, 1] as const) {
                for (const dy of [-0.02, 0.03, 0.08]) {
                    ctx.beginPath();
                    ctx.moveTo(dir * 0.17 * s, (0.14 + dy) * s);
                    ctx.lineTo(dir * 0.52 * s, (0.10 + dy * 1.6) * s);
                    ctx.stroke();
                }
            }
        },
    },
    {
        id: 'flowers',
        draw: (ctx, s) => {
            const tints = ['#F2A6C0', '#F5D06A', '#B7A6F2', '#F2A6C0', '#8FD6A8'];
            // Swept from -60 to +60 degrees off vertical so the garland sits across the crown of
            // the head, and rotates with it because the whole mask is drawn in head space.
            for (let i = 0; i < 9; i++) {
                const a = -Math.PI / 3 + (i / 8) * ((2 * Math.PI) / 3);
                ctx.save();
                ctx.translate(Math.sin(a) * 0.70 * s, -Math.cos(a) * 0.74 * s - 0.10 * s);
                const tint = tints[i % tints.length];
                for (let p = 0; p < 5; p++) petal(ctx, s * 0.62, (p / 5) * Math.PI * 2, 0.10 * s, tint);
                ctx.fillStyle = '#F7E7A8';
                ctx.beginPath();
                ctx.arc(0, 0, 0.035 * s, 0, Math.PI * 2);
                ctx.fill();
                ctx.restore();
            }
        },
    },
    {
        id: 'shades',
        draw: (ctx, s) => {
            glasses(ctx, s, 'rgba(12,12,16,0.86)', '#111114');
            ctx.fillStyle = '#241C16';
            ctx.beginPath();
            ctx.moveTo(-0.26 * s, 0.26 * s);
            ctx.quadraticCurveTo(0, 0.14 * s, 0.26 * s, 0.26 * s);
            ctx.quadraticCurveTo(0.20 * s, 0.40 * s, 0, 0.36 * s);
            ctx.quadraticCurveTo(-0.20 * s, 0.40 * s, -0.26 * s, 0.26 * s);
            ctx.fill();
        },
    },
    {
        id: 'crown',
        draw: (ctx, s) => {
            ctx.fillStyle = '#F2C14E';
            ctx.beginPath();
            ctx.moveTo(-0.62 * s, -0.60 * s);
            ctx.lineTo(-0.40 * s, -1.02 * s);
            ctx.lineTo(-0.18 * s, -0.70 * s);
            ctx.lineTo(0, -1.16 * s);
            ctx.lineTo(0.18 * s, -0.70 * s);
            ctx.lineTo(0.40 * s, -1.02 * s);
            ctx.lineTo(0.62 * s, -0.60 * s);
            ctx.closePath();
            ctx.fill();
            ctx.fillStyle = '#D9A82F';
            ctx.fillRect(-0.62 * s, -0.62 * s, 1.24 * s, 0.16 * s);
            for (const [dx, tint] of [[-0.40, '#E0556B'], [0, '#5AA9E6'], [0.40, '#6BCB77']] as const) {
                ctx.fillStyle = tint;
                ctx.beginPath();
                ctx.arc(dx * s, -0.54 * s, 0.055 * s, 0, Math.PI * 2);
                ctx.fill();
            }
        },
    },
] as const;

export function maskLabel(id: string): string {
    switch (id) {
        case 'dog':     return t('camera.maskDog', 'Dog');
        case 'bunny':   return t('camera.maskBunny', 'Bunny');
        case 'cat':     return t('camera.maskCat', 'Cat');
        case 'flowers': return t('camera.maskFlowers', 'Flowers');
        case 'shades':  return t('camera.maskShades', 'Shades');
        case 'crown':   return t('camera.maskCrown', 'Crown');
        default:        return t('camera.maskNone', 'None');
    }
}

export function findMask(id: string): CameraMask | null {
    return CAMERA_MASKS.find(m => m.id === id) ?? null;
}

export function drawMask(
    ctx: CanvasRenderingContext2D,
    mask: CameraMask,
    anchor: FaceAnchor,
    w: number,
    h: number,
) {
    const sx = anchor.fx * w;
    const sy = anchor.fy * h;
    if (!Number.isFinite(sx) || !Number.isFinite(sy) || sx < 1 || sy < 1) return;
    ctx.save();
    ctx.translate(anchor.u * w, anchor.v * h);
    ctx.scale(sx, sy);
    ctx.rotate(anchor.roll);
    mask.draw(ctx, 1);
    ctx.restore();
}
