"""Scale launcher artwork to fill most of the square canvas (bigger home-screen icon)."""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent

# Fraction of canvas (max side) used by scaled content — Chrome-style “big” icons.
FILL_RATIO = 0.90
CANVAS = 1024


def expand_to_canvas(rgba: np.ndarray, size: int, fill_ratio: float) -> np.ndarray:
    a = rgba[:, :, 3] > 40
    ys, xs = np.where(a)
    if len(xs) == 0:
        return rgba
    x0, x1 = xs.min(), xs.max()
    y0, y1 = ys.min(), ys.max()
    crop = rgba[y0 : y1 + 1, x0 : x1 + 1]
    h, w = crop.shape[:2]
    target_px = int(size * fill_ratio)
    scale = target_px / max(w, h)
    nw, nh = max(1, int(round(w * scale))), max(1, int(round(h * scale)))
    pil = Image.fromarray(crop).resize((nw, nh), Image.Resampling.LANCZOS)
    scaled = np.array(pil)
    out = np.zeros((size, size, 4), dtype=np.uint8)
    ox = (size - nw) // 2
    oy = (size - nh) // 2
    out[oy : oy + nh, ox : ox + nw] = scaled
    return out


def recenter_opaque_mass(rgba: np.ndarray, size: int, alpha_threshold: int = 40) -> np.ndarray:
    """Shift pixels so alpha-weighted centroid is at the canvas center (fixes lopsided masks)."""
    mask = rgba[:, :, 3] > alpha_threshold
    if not mask.any():
        return rgba
    ys, xs = np.where(mask)
    weights = rgba[ys, xs, 3].astype(np.float64)
    wsum = weights.sum()
    cx = float(np.sum(xs.astype(np.float64) * weights) / wsum)
    cy = float(np.sum(ys.astype(np.float64) * weights) / wsum)
    dx = int(round(size / 2 - cx))
    dy = int(round(size / 2 - cy))
    if dx == 0 and dy == 0:
        return rgba
    out = np.zeros((size, size, 4), dtype=np.uint8)
    yd, xd = np.meshgrid(
        np.arange(size, dtype=np.int32),
        np.arange(size, dtype=np.int32),
        indexing="ij",
    )
    sx = xd - dx
    sy = yd - dy
    valid = (sx >= 0) & (sx < size) & (sy >= 0) & (sy < size)
    out[yd[valid], xd[valid]] = rgba[sy[valid], sx[valid]]
    return out


def main() -> None:
    for rel in [
        ROOT / "assets" / "images" / "qride_app_icon.png",
        ROOT / "assets" / "images" / "qride_logo_mark.png",
    ]:
        if not rel.exists():
            continue
        arr = np.array(Image.open(rel).convert("RGBA"))
        out = expand_to_canvas(arr, CANVAS, FILL_RATIO)
        out = recenter_opaque_mass(out, CANVAS)
        Image.fromarray(out).save(rel, format="PNG", optimize=True)
        print(f"expanded: {rel.name}")


if __name__ == "__main__":
    main()
