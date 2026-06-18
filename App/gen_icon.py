#!/usr/bin/env python3
"""Generate Ember's app icon: a warm-orange flame on a soft gradient.

Local, dependency-light (Pillow only), no network. Renders at 4x and
downsamples for crisp antialiasing. Output: a 1024x1024 PNG with no alpha
(iOS app icons must be fully opaque).
"""
from PIL import Image, ImageDraw
import math

S = 1024
SS = 4               # supersample factor
W = S * SS

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

# --- Background: warm vertical gradient (deep amber -> soft cream) ---
top = (255, 138, 42)      # warm orange
bot = (255, 198, 120)     # lighter peach
bg = Image.new("RGB", (W, W), bot)
px = bg.load()
for y in range(W):
    row = lerp(top, bot, y / W)
    for x in range(W):
        px[x, y] = row

draw = ImageDraw.Draw(bg)

def flame(cx, cy, h, w, color):
    """A teardrop flame: pointed top, rounded bottom, gentle S-curve sides."""
    pts = []
    n = 80
    # left side: bottom -> top
    for i in range(n + 1):
        t = i / n
        y = cy - h * t
        # width tapers to a point at top; slight wobble for a natural curl
        bulge = math.sin(t * math.pi) ** 0.7
        curl = 0.12 * math.sin(t * math.pi * 1.0)
        x = cx - w * bulge * (1 - 0.15 * t) + w * curl
        pts.append((x, y))
    # right side: top -> bottom
    for i in range(n + 1):
        t = 1 - i / n
        y = cy - h * t
        bulge = math.sin(t * math.pi) ** 0.7
        curl = 0.12 * math.sin(t * math.pi * 1.0)
        x = cx + w * bulge * (1 - 0.15 * t) + w * curl
        pts.append((x, y))
    draw.polygon(pts, fill=color)

cx = W * 0.5
base = W * 0.74          # flame base y
# Outer flame (rich orange-red), inner (bright orange), core (warm yellow)
flame(cx, base, h=W * 0.56, w=W * 0.22, color=(214, 64, 16))
flame(cx, base - W * 0.02, h=W * 0.44, w=W * 0.155, color=(255, 140, 24))
flame(cx, base - W * 0.04, h=W * 0.30, w=W * 0.095, color=(255, 214, 90))

# Downsample for antialiasing and flatten (no alpha)
icon = bg.resize((S, S), Image.LANCZOS).convert("RGB")
out = "Ember/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
icon.save(out, "PNG")
print("wrote", out, icon.size, icon.mode)
