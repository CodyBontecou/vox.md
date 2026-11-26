#!/usr/bin/env python3
"""Generates the dark and tinted iOS home-screen icon variants from the light AppIcon.

iOS 18+ draws its own backdrop behind the dark and tinted appearances, so both
variants must be the glyph alone on transparency (Apple HIG, "App icons"):

  - AppIcon-1024-dark.png    the six white bars and the orange dot, in the
                              light icon's exact pixels, on transparency
                              (no #0F0F0F tile, grid or corner crosshairs)
  - AppIcon-1024-tinted.png  the same glyph in greyscale: bars keep their
                              light-grey shading, the dot becomes a mid/light
                              grey so it still reads once the system tints it

Both are derived from the canonical light icon so the geometry stays
pixel-identical to it:

  alpha   brightness of the bars / saturation of the orange dot above the
          near-black background, clipped to a slightly dilated copy of the
          Android themed glyph (apps/android/branding/launcher-monochrome-1024.png,
          same geometry within 1px) so the faint grid, crosshairs and bar
          shadows are dropped.
  colour  the light icon's own pixels, bled outward a few pixels so the
          anti-aliased edges are not darkened by the old background.

Usage: python3 scripts/generate-ios-icon-variants.py [--check]
Only needs Pillow.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

REPO_ROOT = Path(__file__).resolve().parents[1]
ICONSET = REPO_ROOT / "Voxboard/Assets.xcassets/AppIcon.appiconset"
LIGHT_ICON = ICONSET / "AppIcon-1024.png"
DARK_ICON = ICONSET / "AppIcon-1024-dark.png"
TINTED_ICON = ICONSET / "AppIcon-1024-tinted.png"
GLYPH_MASK = REPO_ROOT / "apps/android/branding/launcher-monochrome-1024.png"

SIZE = 1024
# Background of the light icon is ~#16161A..#1F1E1E with grid lines just above;
# bars are #D4..#FC. Brightness below LUMA_FLOOR is background, above LUMA_CEIL is solid bar.
LUMA_FLOOR = 40
LUMA_CEIL = 190
# The dot is #FE8D0F; red minus blue separates it from the grey bars and background.
ORANGE_FLOOR = 20
ORANGE_CEIL = 220
# Dilation of the Android glyph mask, in pixels, so the clip never eats real edges.
MASK_GROW = 9
# Bleed radius for the colour layer (edge pixels take their interior neighbour's colour).
COLOUR_BLEED = 7
# Grey used for the dot in the tinted variant (orange luma is ~160; slightly lighter
# keeps it legible after the system's tint, but still distinct from the bars).
TINTED_DOT_GREY = 176


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def ramp(channel: Image.Image, floor: int, ceil: int) -> Image.Image:
    scale = 255.0 / (ceil - floor)
    return channel.point(lambda v: max(0, min(255, round((v - floor) * scale))))


def build_alpha(light: Image.Image, glyph_mask: Image.Image) -> tuple[Image.Image, Image.Image]:
    """Returns (glyph alpha, dot alpha)."""
    red, _, blue = light.split()
    luma = light.convert("L")
    orange = ImageChops.subtract(red, blue)
    dot_alpha = ramp(orange, ORANGE_FLOOR, ORANGE_CEIL)
    bar_alpha = ramp(luma, LUMA_FLOOR, LUMA_CEIL)
    clip = glyph_mask.filter(ImageFilter.MaxFilter(MASK_GROW)).point(lambda v: 255 if v > 0 else 0)
    alpha = ImageChops.multiply(ImageChops.lighter(bar_alpha, dot_alpha), clip)
    return alpha, ImageChops.multiply(dot_alpha, clip)


def bleed(light: Image.Image, alpha: Image.Image) -> Image.Image:
    """Pushes solid interior colours outward over the anti-aliased rim."""
    solid = alpha.point(lambda v: 255 if v >= 250 else 0)
    colour = Image.new("RGB", light.size, (0, 0, 0))
    colour.paste(light, mask=solid)
    weight = solid
    for _ in range(COLOUR_BLEED):
        grown = colour.filter(ImageFilter.MaxFilter(3))
        grown_weight = weight.filter(ImageFilter.MaxFilter(3))
        fresh = ImageChops.subtract(grown_weight, weight)
        colour.paste(grown, mask=fresh)
        weight = grown_weight
    return colour


def build_variants() -> tuple[Image.Image, Image.Image]:
    if not LIGHT_ICON.exists():
        fail(f"light icon not found: {LIGHT_ICON}")
    if not GLYPH_MASK.exists():
        fail(f"glyph mask not found: {GLYPH_MASK}")
    light = Image.open(LIGHT_ICON).convert("RGB")
    glyph = Image.open(GLYPH_MASK).convert("RGBA").getchannel("A")
    if light.size != (SIZE, SIZE) or glyph.size != (SIZE, SIZE):
        fail(f"expected {SIZE}x{SIZE} inputs, got {light.size} and {glyph.size}")

    alpha, dot_alpha = build_alpha(light, glyph)
    colour = bleed(light, alpha)

    dark = colour.convert("RGBA")
    dark.putalpha(alpha)

    grey = colour.convert("L")
    dot_region = dot_alpha.point(lambda v: 255 if v > 0 else 0).filter(ImageFilter.MaxFilter(COLOUR_BLEED * 2 + 1))
    grey.paste(TINTED_DOT_GREY, mask=dot_region)
    tinted = Image.merge("RGBA", (grey, grey, grey, alpha))
    return dark, tinted


def same_pixels(path: Path, image: Image.Image) -> bool:
    if not path.exists():
        return False
    existing = Image.open(path).convert("RGBA")
    return existing.size == image.size and ImageChops.difference(existing, image).getbbox() is None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="exit 1 if the committed variants are out of date")
    arguments = parser.parse_args()

    dark, tinted = build_variants()
    outputs = {DARK_ICON: dark, TINTED_ICON: tinted}
    if arguments.check:
        stale = [path for path, image in outputs.items() if not same_pixels(path, image)]
        for path in stale:
            print(f"stale: {path.relative_to(REPO_ROOT)}", file=sys.stderr)
        raise SystemExit(1 if stale else 0)
    for path, image in outputs.items():
        image.save(path, optimize=True)
        print(f"wrote {path.relative_to(REPO_ROOT)}")


if __name__ == "__main__":
    main()
