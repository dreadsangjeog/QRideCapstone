"""Remove stray ink on the right of QRide mark PNGs (leftover text fragments).

Keeps pixels connected to the artwork near the left (bicycle). Any ink islands
only reachable through the far-right are cleared.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent


def ink_mask(rgba: np.ndarray) -> np.ndarray:
    a = rgba[:, :, 3] > 40
    mx = rgba[:, :, :3].max(axis=2)
    mn = rgba[:, :, :3].min(axis=2)
    sat = mx - mn
    return a & (sat > 22) & (mx < 248)


def reachable_from_left(ink: np.ndarray, seed_width: int = 420) -> np.ndarray:
    """4-connected closure of ink pixels touching columns [0, seed_width)."""
    h, w = ink.shape
    reach = np.zeros_like(ink, dtype=bool)
    reach[:, : min(seed_width, w)] = ink[:, : min(seed_width, w)]
    while True:
        n = np.zeros_like(reach)
        n[1:, :] |= reach[:-1, :]
        n[:-1, :] |= reach[1:, :]
        n[:, 1:] |= reach[:, :-1]
        n[:, :-1] |= reach[:, 1:]
        new = (n & ink) & ~reach
        if not new.any():
            break
        reach |= new
    return reach


def clean_rgba(path: Path) -> np.ndarray:
    im = Image.open(path).convert("RGBA")
    arr = np.array(im)
    ink = ink_mask(arr)
    reach = reachable_from_left(ink, seed_width=420)
    stray = ink & ~reach
    out = arr.copy()
    out[stray, 3] = 0
    out[stray, :3] = 0
    removed = int(stray.sum())
    print(f"{path.name}: removed {removed} stray pixels")
    return out


def main() -> None:
    targets = [
        ROOT / "assets" / "images" / "qride_logo_mark.png",
        ROOT / "assets" / "images" / "qride_app_icon.png",
    ]
    for p in targets:
        if not p.exists():
            print(f"skip missing {p}", file=sys.stderr)
            continue
        out = clean_rgba(p)
        Image.fromarray(out).save(p, format="PNG", optimize=True)


if __name__ == "__main__":
    main()
