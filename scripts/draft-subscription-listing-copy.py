#!/usr/bin/env python3
"""Draft targeted listing corrections for approval; performs NO network requests."""
import difflib
import json
from pathlib import Path
import unicodedata

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs/evidence/subscription-transition-20261029"
TRANSLATIONS = json.loads((OUT / "pricing-copy-translations.json").read_text())
LEGAL = "Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/\nPrivacy: https://vox.isolated.tech/privacy.html"


def numbers(text):
    return "".join(str(unicodedata.digit(c)) if c.isdigit() else c for c in text)


def main():
    drafts, diffs = [], []
    for platform in ("ios", "mac"):
        rows = json.loads((OUT / f"{platform}-localizations-before.json").read_text())["data"]
        for row in rows:
            attrs = row["attributes"]
            locale = attrs["locale"]
            lang = locale if locale in TRANSLATIONS else locale.split("-")[0]
            pricing = TRANSLATIONS[lang]
            before = attrs["description"]
            blocks = before.split("\n\n")
            matches = [i for i, block in enumerate(blocks) if "15" in numbers(block)]
            assert len(matches) == 1, (platform, locale, matches)
            index = matches[0]
            blocks[index] = pricing
            if index > 0 and len(blocks[index - 1]) < 80:
                blocks[index - 1] = ""
            # Old Mac listings also promised 'no subscription' in the introductory
            # em-dash clause and their last feature bullet. Preserve other copy.
            if platform == "mac" and any(b.startswith("•") for b in blocks):
                blocks[0] = blocks[0].split("—")[0].strip().rstrip(".") + "."
                for i, block in enumerate(blocks):
                    if block.startswith("•"):
                        lines = block.splitlines()
                        assert lines[-1].startswith("•"), (platform, locale)
                        blocks[i] = "\n".join(lines[:-1])
            after = "\n\n".join(b for b in blocks if b.strip()) + "\n\n" + LEGAL
            assert len(after) <= 4000 and len(pricing) <= 4000, (platform, locale, len(after))
            assert "15" not in numbers(after), (platform, locale)
            drafts.append({"platform": platform, "localization_id": row["id"], "locale": locale,
                           "description": after, "whatsNew": pricing,
                           "approval_status": "AWAITING_OWNER_APPROVAL_NOT_UPLOADED"})
            diffs.extend(difflib.unified_diff(before.splitlines(keepends=True), after.splitlines(keepends=True),
                         fromfile=f"{platform}/{locale}/before", tofile=f"{platform}/{locale}/proposed"))
    (OUT / "listing-copy-proposed.json").write_text(json.dumps(drafts, indent=2, ensure_ascii=False) + "\n")
    (OUT / "listing-copy.diff").write_text("".join(diffs))
    print(f"Drafted {len(drafts)} version-localization changes; no API requests or uploads.")


if __name__ == "__main__":
    main()
