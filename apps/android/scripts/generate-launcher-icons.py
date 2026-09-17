#!/usr/bin/env python3
"""Generates the complete Android launcher icon set from the canonical iOS app icon.

The phone and Wear modules historically shipped without android:icon, so Play
installs rendered the platform default glyph. Every launcher variant is derived
from the single 1024px iOS AppIcon so the brands stay lock-step:

  - mipmap-anydpi-v26/ic_launcher(.xml|_round.xml) adaptive icons
  - mipmap-*/ic_launcher_foreground.png  full artwork in the 66/108 safe zone
  - mipmap-*/ic_launcher_monochrome.png  waveform-only glyph for themed icons
  - mipmap-*/ic_launcher(.png|_round.png)  legacy square and circle fallbacks
  - values/ic_launcher_colors.xml  background tint sampled from the artwork edge
  - drawable/ic_vox_waveform.xml  vector glyph for tinted surfaces such as the
    quick-settings capture tile, measured from the artwork bars and accent dot
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
DOT_MAX_SIDE = 100
EXPECTED_BARS = 6

VECTOR_XML = (
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
    '    android:width="24dp"\n'
    '    android:height="24dp"\n'
    '    android:viewportWidth="{viewport}"\n'
    '    android:viewportHeight="{viewport}">\n'
    '    <path\n'
    '        android:fillColor="#FFFFFFFF"\n'
    '        android:pathData="{bars}" />\n'
    '    <path\n'
    '        android:fillColor="{dot_color}"\n'
    '        android:pathData="{dot}" />\n'
    "</vector>\n"
)


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

    The artwork edge carries a faint grid texture whose brightness drifts a few
    levels above the sampled background, which could betray a square seam on
    circular masks. The outer band fades to transparent so the artwork blends
    into the adaptive background; the waveform glyph sits far inside and is
    untouched.
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
    canvas.paste(scaled, (offset, offset), scaled)
    return canvas


def content_alpha(artwork: Image.Image) -> Image.Image:
    """Masks bright artwork content (waveform bars, accent dot) over texture."""
    red, green, blue = artwork.convert("RGB").split()
    brightest = ImageChops.lighter(ImageChops.lighter(red, green), blue)
    ramp = [0 if value < 60 else 255 if value > 130 else round((value - 60) * 255 / 70) for value in range(256)]
    return brightest.point(ramp)


def build_monochrome_source(artwork: Image.Image) -> Image.Image:
    """Reduces the artwork to an opaque-white waveform glyph.

    Bright bars and the accent dot become opaque; the faint grid texture and
    near-black canvas stay transparent so launcher theming tints only the glyph.
    """
    alpha = content_alpha(artwork)
    white = Image.new("L", artwork.size, 255)
    return Image.merge("RGBA", (white, white, white, alpha))


def measure_glyph(artwork: Image.Image) -> tuple[list[tuple[int, int, int, int]], tuple[int, int, int, int]]:
    """Locates the waveform bar and accent-dot bounds via connected components."""
    alpha = content_alpha(artwork)
    width, height = alpha.size
    data = alpha.tobytes()
    seen = bytearray(width * height)
    bounds: list[tuple[int, int, int, int]] = []
    for seed in range(width * height):
        if data[seed] < 129 or seen[seed]:
            continue
        seen[seed] = 1
        stack = [seed]
        min_x = max_x = seed % width
        min_y = max_y = seed // width
        while stack:
            index = stack.pop()
            x, y = index % width, index // width
            min_x, max_x = min(min_x, x), max(max_x, x)
            min_y, max_y = min(min_y, y), max(max_y, y)
            for offset in (-1, 0, 1):
                for vertical in (-1, 0, 1):
                    if not offset and not vertical:
                        continue
                    neighbor_x, neighbor_y = x + offset, y + vertical
                    if 0 <= neighbor_x < width and 0 <= neighbor_y < height:
                        neighbor = neighbor_y * width + neighbor_x
                        if data[neighbor] >= 129 and not seen[neighbor]:
                            seen[neighbor] = 1
                            stack.append(neighbor)
        bounds.append((min_x, min_y, max_x, max_y))

    bars = [box for box in bounds if max(box[2] - box[0], box[3] - box[1]) >= DOT_MAX_SIDE]
    dots = [box for box in bounds if max(box[2] - box[0], box[3] - box[1]) < DOT_MAX_SIDE]
    if len(bars) != EXPECTED_BARS or len(dots) != 1:
        fail(
            "expected the artwork to contain "
            f"{EXPECTED_BARS} waveform bars and 1 accent dot, measured "
            f"{len(bars)} bars and {len(dots)} dots"
        )
    bars.sort(key=lambda box: box[0])
    return bars, dots[0]


def _format(value: float) -> str:
    text = f"{value:.1f}"
    return text[:-2] if text.endswith(".0") else text


def _capsule_path(left: float, top: float, right: float, bottom: float) -> str:
    radius = (right - left) / 2
    return " ".join(
        (
            f"M{_format(left)},{_format(top + radius)}",
            f"A{_format(radius)},{_format(radius)} 0 0 1 {_format(left + radius)},{_format(top)}",
            f"L{_format(right - radius)},{_format(top)}",
            f"A{_format(radius)},{_format(radius)} 0 0 1 {_format(right)},{_format(top + radius)}",
            f"L{_format(right)},{_format(bottom - radius)}",
            f"A{_format(radius)},{_format(radius)} 0 0 1 {_format(right - radius)},{_format(bottom)}",
            f"L{_format(left + radius)},{_format(bottom)}",
            f"A{_format(radius)},{_format(radius)} 0 0 1 {_format(left)},{_format(bottom - radius)}",
            "Z",
        )
    )


def _circle_path(center_x: float, center_y: float, radius: float) -> str:
    return " ".join(
        (
            f"M{_format(center_x - radius)},{_format(center_y)}",
            f"A{_format(radius)},{_format(radius)} 0 1 1 {_format(center_x + radius)},{_format(center_y)}",
            f"A{_format(radius)},{_format(radius)} 0 1 1 {_format(center_x - radius)},{_format(center_y)}",
            "Z",
        )
    )


def build_tile_vector(artwork: Image.Image) -> str:
    """Emits the tintable waveform vector for quick-settings and shortcut icons."""
    bars, dot = measure_glyph(artwork)
    bar_paths = " ".join(
        _capsule_path(min_x, min_y, max_x + 1, max_y + 1) for min_x, min_y, max_x, max_y in bars
    )
    dot_left, dot_top, dot_right, dot_bottom = dot
    dot_width = (dot_right - dot_left + 1) / 2
    dot_center = ((dot_left + dot_right + 1) / 2, (dot_top + dot_bottom + 1) / 2)
    dot_rgb = artwork.getpixel((round(dot_center[0]), round(dot_center[1])))
    dot_color = "#{:02X}{:02X}{:02X}".format(*dot_rgb[:3])
    return VECTOR_XML.format(
        viewport=artwork.width,
        bars=bar_paths,
        dot_color=dot_color,
        dot=_circle_path(dot_center[0], dot_center[1], dot_width),
    )


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
    parser.add_argument(
        "--emit-tile-icon",
        action="store_true",
        help="Also emits the tintable waveform vector for tiles and shortcuts.",
    )
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
    monochrome_source = build_monochrome_source(artwork)

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

    if arguments.emit_tile_icon:
        drawable_dir = output_root / "drawable"
        drawable_dir.mkdir(parents=True, exist_ok=True)
        tile_path = drawable_dir / "ic_vox_waveform.xml"
        tile_path.write_text(build_tile_vector(artwork), encoding="utf-8")
        written.append(tile_path)

    print(f"sampled adaptive background {background_hex} from {icon_path.name}")
    print(f"wrote {len(written)} launcher icon files under {output_root}")


if __name__ == "__main__":
    main()
