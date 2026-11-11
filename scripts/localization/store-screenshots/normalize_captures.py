#!/usr/bin/env python3
"""Normalize raw simulator captures into artifacts/localization/store-signal-captures/_ready/.

Raw iPad (landscape) and iPhone Duo inner-panel screenshots come out of the simulator in the
panel's portrait buffer, with the UI turned 90°. This rotates them upright; everything else
is copied as-is. Run after a capture pass, before render.mjs.
"""
import sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[3] / "artifacts/localization/store-signal-captures"
READY = ROOT / "_ready"
# PIL rotates counter-clockwise for positive angles. The iPad buffer shows the landscape UI
# turned 90° clockwise; the Duo inner panel's buffer is turned the other way.
ROTATION = {
    ("ipad", "capture"): 90, ("ipad", "library"): 90,
    ("duo", "inner-capture"): 270, ("duo", "inner-library"): 270, ("duo", "tabletop"): 270,
}


def main() -> None:
    count = 0
    for raw in sorted(ROOT.glob("*/*/*.png")):
        if raw.parts[-4] == "_ready" or raw.parent.parent.name.startswith("_"):
            continue
        locale, device, name = raw.parent.parent.name, raw.parent.name, raw.stem
        im = Image.open(raw)
        angle = ROTATION.get((device, name))
        if angle and im.height > im.width:
            im = im.rotate(angle, expand=True)
        dest = READY / locale / device / f"{name}.png"
        dest.parent.mkdir(parents=True, exist_ok=True)
        im.save(dest)
        count += 1
    print(f"normalized {count} captures -> {READY}")


if __name__ == "__main__":
    main()
