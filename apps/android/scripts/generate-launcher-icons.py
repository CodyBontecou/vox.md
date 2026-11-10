#!/usr/bin/env python3
"""Generates the complete Android launcher icon set from the canonical iOS app icon.

The phone and Wear modules historically shipped without android:icon, so Play
installs rendered the platform default glyph. Every launcher variant is derived
from the single 1024px iOS AppIcon so the brands stay lock-step:

  - mipmap-anydpi-v26/ic_launcher(.xml|_round.xml) adaptive icons
  - mipmap-*/ic_launcher_foreground.png  full artwork in the 66/108 safe zone
  - mipmap-*/ic_launcher_monochrome.png  themed-icon glyph from
    apps/android/branding/launcher-monochrome-1024.png (white on transparency)
  - mipmap-*/ic_launcher(.png|_round.png)  legacy square and circle fallbacks
  - values/ic_launcher_colors.xml  background tint sampled from the artwork edge

The quick-settings tile and shortcut glyph (drawable/ic_vox_waveform.xml) is a
committed resource in app/src/main/res, independent of the launcher artwork.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

DENSITY_SCALERS = {
    "mdpi": 1.0,
    "hdpi": 1.5,
    "xhdpi": 2.0,
    "xxhdpi": 3.0,
    "xxxhdpi": 4.0,
}
LEGACY_BASE_DP = 48
FOREGROUND_BASE_DP = 108
SAFE_ZONE_RATIO = 66.0 / 108.0
EDGE_FADE_RATIO = 0.06

ADAPTIVE_ICON_XML = (
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <background android:drawable="@color/ic_launcher_background" />\n'
    '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
    '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
    "</adaptive-icon>\n"
)
COLORS_XML = (
    '<?xml version="1.0" encoding="utf-8"?>\n'
    "<resources>\n"
    '    <color name="ic_launcher_background">{value}</color>\n'
    "</resources>\n"
)

REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_ICON = (
    REPO_ROOT / "Voxboard/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
)
DEFAULT_MONOCHROME = REPO_ROOT / "apps/android/branding/launcher-monochrome-1024.png"

def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def sample_background(artwork: Image.Image) -> tuple[int, int, int]:
    """Averages the artwork border so the adaptive background extends it seamlessly."""
    width, height = artwork.size
    samples: list[tuple[int, ...]] = []
    for x in range(0, width, 8):
        samples.append(artwork.getpixel((x, 0)))
        samples.append(artwork.getpixel((x, height - 1)))
    for y in range(0, height, 8):
        samples.append(artwork.getpixel((0, y)))
        samples.append(artwork.getpixel((width - 1, y)))
    channels = zip(*samples)
    return tuple(round(sum(channel) / len(channel)) for channel in channels)  # type: ignore[return-value]


def place_in_safe_zone(layer: Image.Image, canvas_size: int) -> Image.Image:
    """Centers a layer inside the 66/108 adaptive safe zone on transparency.

    Any drift between the artwork edge and the sampled background could betray
    a square seam on circular masks, so the outer band fades to transparent and
    the artwork blends into the adaptive background; the glyph sits far inside
    and is untouched.
    """
    faded = layer.convert("RGBA").copy()
    width, height = faded.size
    band = max(1, round(min(width, height) * EDGE_FADE_RATIO))
    ramps = []
    for extent, fade in ((width, band), (height, band)):
        ramp = [round(255 * position / fade) for position in range(fade)]
        ramps.append(ramp + [255] * (extent - 2 * fade) + ramp[::-1])
    mask = Image.new("L", (width, height), 255)
    pixels = mask.load()
    for y in range(height):
        row_alpha = ramps[1][y]
        for x in range(width):
            pixels[x, y] = min(ramps[0][x], row_alpha)
    faded.putalpha(ImageChops.multiply(faded.getchannel("A"), mask))

    canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    inner = max(1, round(canvas_size * SAFE_ZONE_RATIO))
    scaled = faded.resize((inner, inner), Image.LANCZOS)
    offset = (canvas_size - inner) // 2
    # Plain paste onto the empty canvas: masking with the layer's own alpha would
    # blend the faded edge toward transparent black and draw a dark square seam.
    canvas.paste(scaled, (offset, offset))
    return canvas


def load_monochrome(path: Path, size: int) -> Image.Image:
    """Loads the hand-drawn themed-icon glyph: opaque white artwork on transparency."""
    if not path.is_file():
        fail(f"monochrome glyph not found: {path}")
    glyph = Image.open(path).convert("RGBA")
    if glyph.size != (size, size):
        fail(f"monochrome glyph must be {size}x{size} to match the icon, got {glyph.width}x{glyph.height}")
    white = Image.new("L", glyph.size, 255)
    return Image.merge("RGBA", (white, white, white, glyph.getchannel("A")))


def build_legacy(artwork: Image.Image, size: int, circle: bool) -> Image.Image:
    icon = artwork.resize((size, size), Image.LANCZOS).convert("RGBA")
    if circle:
        supersampled = size * 4
        mask = Image.new("L", (supersampled, supersampled), 0)
        ImageDraw.Draw(mask).ellipse(
            (0, 0, supersampled - 1, supersampled - 1), fill=255
        )
        icon.putalpha(mask.resize((size, size), Image.LANCZOS))
    return icon


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--icon", type=Path, default=DEFAULT_ICON)
    parser.add_argument("--out", type=Path, required=True, help="Module res output directory.")
    parser.add_argument("--monochrome", type=Path, default=DEFAULT_MONOCHROME)
    arguments = parser.parse_args()

    icon_path = arguments.icon.resolve()
    output_root = arguments.out.resolve()
    if not icon_path.is_file():
        fail(f"source icon not found: {icon_path}")
    artwork = Image.open(icon_path).convert("RGB")
    if artwork.width != artwork.height:
        fail(f"source icon must be square, got {artwork.width}x{artwork.height}")

    background = sample_background(artwork)
    background_hex = "#{:02X}{:02X}{:02X}".format(*background)
    monochrome_source = load_monochrome(arguments.monochrome.resolve(), artwork.width)

    written: list[Path] = []
    for density, scale in DENSITY_SCALERS.items():
        density_dir = output_root / f"mipmap-{density}"
        legacy_size = round(LEGACY_BASE_DP * scale)
        foreground_size = round(FOREGROUND_BASE_DP * scale)

        layers = {
            "ic_launcher.png": build_legacy(artwork, legacy_size, circle=False),
            "ic_launcher_round.png": build_legacy(artwork, legacy_size, circle=True),
            "ic_launcher_foreground.png": place_in_safe_zone(artwork, foreground_size),
            "ic_launcher_monochrome.png": place_in_safe_zone(
                monochrome_source, foreground_size
            ),
        }
        for filename, image in layers.items():
            path = density_dir / filename
            path.parent.mkdir(parents=True, exist_ok=True)
            image.save(path)
            written.append(path)

    adaptive_dir = output_root / "mipmap-anydpi-v26"
    adaptive_dir.mkdir(parents=True, exist_ok=True)
    for filename in ("ic_launcher.xml", "ic_launcher_round.xml"):
        path = adaptive_dir / filename
        path.write_text(ADAPTIVE_ICON_XML, encoding="utf-8")
        written.append(path)

    values_dir = output_root / "values"
    values_dir.mkdir(parents=True, exist_ok=True)
    colors_path = values_dir / "ic_launcher_colors.xml"
    colors_path.write_text(COLORS_XML.format(value=background_hex), encoding="utf-8")
    written.append(colors_path)

    print(f"sampled adaptive background {background_hex} from {icon_path.name}")
    print(f"wrote {len(written)} launcher icon files under {output_root}")


if __name__ == "__main__":
    main()
