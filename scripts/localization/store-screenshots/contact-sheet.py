#!/usr/bin/env python3
"""Build one review JPEG per locale from artifacts/localization/store-signal/<locale>/."""
import sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[3] / "artifacts/localization/store-signal"
ROW_H = {"iphone": 700, "duo-cover": 700, "ipad": 520, "duo-inner": 520, "mac": 440}

def sheet(locale_dir: Path) -> Path:
    rows = []
    for device, h in ROW_H.items():
        files = sorted((locale_dir / device).glob("*.png"))
        if not files:
            continue
        ims = [Image.open(f).convert("RGB") for f in files]
        ims = [im.resize((round(im.width * h / im.height), h)) for im in ims]
        row = Image.new("RGB", (sum(i.width for i in ims) + 16 * (len(ims) - 1), h), "white")
        x = 0
        for im in ims:
            row.paste(im, (x, 0)); x += im.width + 16
        rows.append(row)
    out = Image.new("RGB", (max(r.width for r in rows), sum(r.height for r in rows) + 24 * (len(rows) - 1)), "white")
    y = 0
    for r in rows:
        out.paste(r, (0, y)); y += r.height + 24
    dest = ROOT / "_sheets" / f"{locale_dir.name}.jpg"
    dest.parent.mkdir(exist_ok=True)
    out.save(dest, quality=82)
    return dest

if __name__ == "__main__":
    wanted = sys.argv[1:]
    for d in sorted(p for p in ROOT.iterdir() if p.is_dir() and not p.name.startswith("_")):
        if not wanted or d.name in wanted:
            print(sheet(d))
