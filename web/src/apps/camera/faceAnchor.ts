import type { CropRegion } from '@/render';
import type { FaceAnchor } from './masks';

export interface FacePush {
    visible: boolean;
    hx?:     number;
    hy?:     number;
    tx?:     number;
    ty?:     number;
}

const MIN_SPAN_PX = 2;

export function computeFaceAnchor(
    data: FacePush,
    crop: CropRegion,
    screenW: number,
    screenH: number,
): FaceAnchor | null {
    if (!data.visible
        || data.hx === undefined || data.hy === undefined
        || data.tx === undefined || data.ty === undefined) return null;

    const hx = data.hx * screenW;
    const hy = data.hy * screenH;
    const dx = data.tx * screenW - hx;
    const dy = data.ty * screenH - hy;
    const span = Math.hypot(dx, dy);
    if (!(span >= MIN_SPAN_PX)) return null;

    return {
        u:    (hx - crop.offsetX) / crop.width,
        v:    (hy - crop.offsetY) / crop.height,
        fx:   span / crop.width,
        fy:   span / crop.height,
        roll: Math.atan2(dx, -dy),
    };
}
