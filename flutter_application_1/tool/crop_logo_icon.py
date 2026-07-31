"""One-off: build qride_logo_mark.png and qride_app_icon.png from qride_logo.png."""
from pathlib import Path

from PIL import Image

root = Path(__file__).resolve().parents[1]
src = root / "assets/images/qride_logo.png"
im = Image.open(src).convert("RGBA")
w, h = im.size
# Bicycle sits in the left ~48% of the 1536px-wide lockup.
cut = int(w * 0.48)
left = im.crop((0, 0, cut, h))
side = max(left.width, left.height)
canvas = Image.new("RGBA", (side, side), (255, 255, 255, 255))
ox = (side - left.width) // 2
oy = (side - left.height) // 2
canvas.paste(left, (ox, oy), left)

mark_path = root / "assets/images/qride_logo_mark.png"
icon_path = root / "assets/images/qride_app_icon.png"
canvas.save(mark_path)
canvas.save(icon_path)
print("Wrote", mark_path, icon_path, canvas.size)
