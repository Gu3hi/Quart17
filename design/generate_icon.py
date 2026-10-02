#!/usr/bin/env python3
"""Generate Quart17 settings icon per DESIGN.md.

Visual: transparent rounded square with a coral glass ring and a
four-point sparkle. Coral accent #FF646E.
Outputs PreferenceLoader sizes into preferences/Resources/.
"""
from PIL import Image, ImageDraw, ImageFilter
import os
import math

CORAL = (255, 100, 110, 255)  # #FF646E


def draw_sparkle(draw, cx, cy, r, color):
    """Four-point sparkle (star) centered at (cx, cy)."""
    points = []
    for i in range(8):
        angle = math.pi / 4 * i - math.pi / 2
        rad = r if i % 2 == 0 else r * 0.28
        points.append((cx + rad * math.cos(angle), cy + rad * math.sin(angle)))
    draw.polygon(points, fill=color)


def generate_icon(size, output_path):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    inset = size * 0.10
    ring_width = max(2, int(size * 0.055))
    radius = size * 0.30

    # Soft outer glow for the glass feel
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.rounded_rectangle(
        [inset, inset, size - inset, size - inset],
        radius=radius,
        outline=CORAL[:3] + (70,),
        width=ring_width * 2,
    )
    glow = glow.filter(ImageFilter.GaussianBlur(radius=max(1, size * 0.025)))
    img = Image.alpha_composite(img, glow)

    d = ImageDraw.Draw(img)
    # Main coral ring
    d.rounded_rectangle(
        [inset, inset, size - inset, size - inset],
        radius=radius,
        outline=CORAL,
        width=ring_width,
    )
    # Inner top-left highlight (glass sheen)
    hi_inset = inset + ring_width + max(1, size * 0.02)
    d.rounded_rectangle(
        [hi_inset, hi_inset, size - hi_inset, size - hi_inset],
        radius=radius * 0.65,
        outline=(255, 255, 255, 55),
        width=max(1, ring_width // 3),
    )

    # Four-point sparkle, coral, centered
    draw_sparkle(d, size / 2, size / 2, size * 0.17, CORAL)
    # Small white glint offset up-left
    draw_sparkle(
        d, size / 2 - size * 0.055, size / 2 - size * 0.075,
        size * 0.055, (255, 255, 255, 210),
    )

    img.save(output_path, "PNG")
    print(f"Generated {output_path} ({size}x{size})")


if __name__ == "__main__":
    script_dir = os.path.dirname(os.path.abspath(__file__))
    out_dir = os.path.normpath(os.path.join(script_dir, "..", "preferences", "Resources"))
    os.makedirs(out_dir, exist_ok=True)
    # PreferenceLoader icon sizes
    generate_icon(87, os.path.join(out_dir, "icon@3x.png"))
    generate_icon(58, os.path.join(out_dir, "icon@2x.png"))
    generate_icon(29, os.path.join(out_dir, "icon.png"))
