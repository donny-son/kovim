#!/usr/bin/env python3
"""
Generate the app icon from logo.png (a transparent foreground shape):
  - assets/AppIcon.iconset/icon_*.png  (pig nose on a white rounded-rect,
                                         transparent outside the rounded shape)
  - assets/AppIcon.icns

The menu-bar logo is rendered as the 🐽 emoji directly in the agent, so this
script no longer produces menubar.png.
"""

from PIL import Image, ImageDraw
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC  = os.path.join(ROOT, "logo.png")

# ── 1. Build a 1024 master: white rounded-rect + centred logo ────────────────
CANVAS = 1024

# macOS Big Sur icon grid: ~100/1024 margin, ~22.5% corner radius on the body.
margin   = round(CANVAS * 100 / 1024)
body     = CANVAS - 2 * margin
radius   = round(body * 0.2249)

master = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

# White rounded-rectangle background; corners stay transparent.
draw = ImageDraw.Draw(master)
draw.rounded_rectangle(
    [margin, margin, margin + body, margin + body],
    radius=radius,
    fill=(255, 255, 255, 255),
)

# Centre the logo inside the body with breathing room (fills ~70% of the body).
logo = Image.open(SRC).convert("RGBA")
target = round(body * 0.70)
lw, lh = logo.size
scale = target / max(lw, lh)
new_size = (max(1, round(lw * scale)), max(1, round(lh * scale)))
logo_resized = logo.resize(new_size, Image.LANCZOS)
offset = ((CANVAS - new_size[0]) // 2, (CANVAS - new_size[1]) // 2)
master.alpha_composite(logo_resized, offset)

print(f"Master: {CANVAS}x{CANVAS}  body={body}  radius={radius}  logo={new_size}")

# ── 2. App Icon sizes (keep RGBA so corners stay transparent) ────────────────
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
    out = master.resize((px, px), Image.LANCZOS)
    out.save(os.path.join(ICONSET_DIR, name), "PNG")
    print(f"  {name} → {px}x{px}")

# ── 3. Compile .icns ──────────────────────────────────────────────────────────
icns_out = os.path.join(ROOT, "assets", "AppIcon.icns")
ret = os.system(f'iconutil -c icns "{ICONSET_DIR}" -o "{icns_out}"')
if ret == 0:
    print(f"\n✅  {icns_out}")
else:
    print("\n⚠️  iconutil failed — check iconset manually")

print("\nDone.")
