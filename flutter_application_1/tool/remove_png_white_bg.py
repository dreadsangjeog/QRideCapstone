"""Make near-white backgrounds transparent in QRide PNG assets."""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets" / "images"
FILES = ["qride_logo_mark.png", "qride_app_icon.png"]


def remove_white_background(rgba: np.ndarray) -> np.ndarray:
    r = rgba[:, :, 0]
    g = rgba[:, :, 1]
    b = rgba[:, :, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    sat = (mx.astype(int) - mn.astype(int))
    lum = (r.astype(int) + g.astype(int) + b.astype(int)) / 3.0
    key = ((r > 252) & (g > 252) & (b > 252)) | ((lum > 246) & (sat < 20))
    out = rgba.copy()
    out[key] = 0
    return out


def main() -> None:
    for name in FILES:
        path = ASSETS / name
        if not path.exists():
            continue
        arr = np.array(Image.open(path).convert("RGBA"))
        n0 = int((arr[:, :, 3] > 0).sum())
        arr = remove_white_background(arr)
        n1 = int((arr[:, :, 3] > 0).sum())
        Image.fromarray(arr).save(path, format="PNG", optimize=True)
        print(f"{name}: opaque pixels {n0} -> {n1}")


if __name__ == "__main__":
    main()
