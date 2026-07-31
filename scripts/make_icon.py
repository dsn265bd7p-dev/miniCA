#!/usr/bin/env python3
"""Generate the miniCA app icon: certificate seal ring + checkmark on petrol blue (#1A6B7A)."""
import math
import os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "miniCA", "Resources",
                   "Assets.xcassets", "AppIcon.appiconset")
SIZES = [16, 32, 64, 128, 256, 512, 1024]

BG = (26, 107, 122, 255)        # #1A6B7A petrol
BG_DARK = (18, 78, 90, 255)
RING = (255, 255, 255, 255)
CHECK = (255, 255, 255, 255)


def rounded_rect_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return m


def draw_icon(size):
    s = 8  # supersampling
    S = size * s
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # vertical gradient background
    for y in range(S):
        t = y / S
        c = tuple(int(BG[i] + (BG_DARK[i] - BG[i]) * t) for i in range(3)) + (255,)
        d.line([(0, y), (S, y)], fill=c)

    cx, cy = S / 2, S / 2 * 0.94
    r_outer = S * 0.30

    # seal wave (scalloped ring)
    lobes, points = 12, 720
    pts = []
    for i in range(points):
        a = 2 * math.pi * i / points
        rr = r_outer * (1 + 0.055 * math.cos(lobes * a))
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    d.polygon(pts, fill=None, outline=RING, width=int(S * 0.022))

    # inner circle
    r_in = r_outer * 0.78
    d.ellipse([cx - r_in, cy - r_in, cx + r_in, cy + r_in],
              outline=RING, width=int(S * 0.020))

    # checkmark
    w = int(S * 0.055)
    p1 = (cx - r_in * 0.48, cy + r_in * 0.02)
    p2 = (cx - r_in * 0.12, cy + r_in * 0.40)
    p3 = (cx + r_in * 0.55, cy - r_in * 0.38)
    d.line([p1, p2, p3], fill=CHECK, width=w, joint="curve")
    for p in (p1, p3):
        d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=CHECK)

    # ribbon tails under the seal
    rw = S * 0.055
    for dx in (-1, 1):
        x0 = cx + dx * S * 0.055
        top = cy + r_outer * 0.92
        bot = cy + r_outer * 1.38
        tip = S * 0.04
        pts = [(x0 - rw, top), (x0 + rw, top), (x0 + rw, bot),
               (x0, bot - tip), (x0 - rw, bot)]
        d.polygon(pts, fill=RING)

    img = img.resize((size, size), Image.LANCZOS)
    # macOS-style rounded corners
    mask = rounded_rect_mask(size, int(size * 0.2237))
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    for size in SIZES:
        draw_icon(size).save(os.path.join(OUT, f"icon_{size}.png"))
    print(f"icons written to {OUT}")


if __name__ == "__main__":
    main()
