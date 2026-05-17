#!/usr/bin/env python3
"""
Generate all icon assets from logo.png:
  - assets/AppIcon.iconset/icon_*.png  (square, full-colour)
  - assets/menubar.png      (22x22, transparent-bg template)
  - assets/menubar@2x.png   (44x44, transparent-bg template)
"""

from PIL import Image
import os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC  = os.path.join(ROOT, "logo.png")

# ── 1. Load & make square ────────────────────────────────────────────────────
img = Image.open(SRC).convert("RGBA")
w, h = img.size
side = max(w, h)                              # 318

# Sample background colour from a corner pixel
bg_r, bg_g, bg_b, _ = img.getpixel((0, 0))
bg = (bg_r, bg_g, bg_b, 255)

square = Image.new("RGBA", (side, side), bg)
offset = ((side - w) // 2, (side - h) // 2)  # centre horizontally
square.paste(img, offset)

print(f"Square base: {side}x{side}  bg={bg[:3]}")

# ── 2. App Icon sizes ────────────────────────────────────────────────────────
ICONSET_DIR = os.path.join(ROOT, "assets", "AppIcon.iconset")
os.makedirs(ICONSET_DIR, exist_ok=True)

ICON_SIZES = [
    ("icon_16x16.png",       16),
    ("icon_16x16@2x.png",    32),
    ("icon_32x32.png",       32),
    ("icon_32x32@2x.png",    64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png",1024),
]

for name, px in ICON_SIZES:
    out = square.resize((px, px), Image.LANCZOS).convert("RGB")
    out.save(os.path.join(ICONSET_DIR, name), "PNG")
    print(f"  {name} → {px}x{px}")

# ── 3. Menubar template images (transparent-bg, black foreground) ─────────────
# Strategy: threshold the light pixels as opaque-black, dark background → transparent
def make_template(base: Image.Image, size: int) -> Image.Image:
    """Resize then convert: bg → transparent, fg → black (template-ready)."""
    small = base.resize((size, size), Image.LANCZOS)
    r, g, b, a = small.split()

    # Perceived brightness of each pixel
    bright = small.convert("L")

    result = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pixels_in  = small.load()
    pixels_out = result.load()
    bright_pix = bright.load()

    for y in range(size):
        for x in range(size):
            lum = bright_pix[x, y]
            # Pixels brighter than midpoint → black template pixel
            # Scale alpha so near-midpoint pixels are semi-transparent (anti-alias)
            if lum > 128:
                alpha = min(255, (lum - 80) * 3)
                pixels_out[x, y] = (0, 0, 0, alpha)
            else:
                pixels_out[x, y] = (0, 0, 0, 0)

    return result

MENUBAR_DIR = os.path.join(ROOT, "assets")

tmpl_1x = make_template(square, 22)
tmpl_2x = make_template(square, 44)

tmpl_1x.save(os.path.join(MENUBAR_DIR, "menubar.png"),    "PNG")
tmpl_2x.save(os.path.join(MENUBAR_DIR, "menubar@2x.png"), "PNG")
print("  menubar.png  → 22x22")
print("  menubar@2x.png → 44x44")

# ── 4. Compile .icns ──────────────────────────────────────────────────────────
icns_out = os.path.join(ROOT, "assets", "AppIcon.icns")
ret = os.system(f'iconutil -c icns "{ICONSET_DIR}" -o "{icns_out}"')
if ret == 0:
    print(f"\n✅  {icns_out}")
else:
    print("\n⚠️  iconutil failed — check iconset manually")

print("\nDone.")
