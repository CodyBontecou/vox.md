#!/usr/bin/env python3
"""Capture the Mac app's store screens for every locale (DEBUG build).

    python3 scripts/localization/store-screenshots/capture_mac.py [--locale ja,de-DE]

Launches build/DerivedData-macOS/.../Vox.md.app with the localization-screenshot hooks,
the signal fixtures seed and the translated seed text, and lets the app write its own
window to artifacts/localization/store-signal-captures/<locale>/mac/<name>.png.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
APP = REPO / "build/DerivedData-macOS/Build/Products/Debug/Vox.md.app/Contents/MacOS/Vox.md"
OUT = REPO / "artifacts/localization/store-signal-captures"
# The app is sandboxed: it can only write inside its own container.
SANDBOX_TMP = Path.home() / "Library/Containers/bontecou.Voxboard/Data/tmp"
SEED = Path(__file__).resolve().parent / "strings" / "seed"

LOCALES = {
    "en-US": ("en", "en_US"), "ar-SA": ("ar", "ar_SA@calendar=gregorian"), "de-DE": ("de", "de_DE"),
    "es-ES": ("es", "es_ES"), "es-MX": ("es-MX", "es_MX"), "fr-FR": ("fr", "fr_FR"),
    "fr-CA": ("fr-CA", "fr_CA"), "hi": ("hi", "hi_IN"), "id": ("id", "id_ID"),
    "it": ("it", "it_IT"), "ja": ("ja", "ja_JP"), "ko": ("ko", "ko_KR"),
    "nl-NL": ("nl", "nl_NL"), "pl": ("pl", "pl_PL"), "pt-BR": ("pt-BR", "pt_BR"),
    "ru": ("ru", "ru_RU"), "th": ("th", "th_TH"), "tr": ("tr", "tr_TR"),
    "uk": ("uk", "uk_UA"), "vi": ("vi", "vi_VN"), "zh-Hans": ("zh-Hans", "zh_CN"),
    "zh-Hant": ("zh-Hant", "zh_TW"),
}
# name -> (story, window size). Frames show the Mac at 1440×900 and the quick
# capture panel at 520×560.
STORIES = {
    "workspace": ("01-capture", "1440x900"),
    "library": ("02-history", "1440x900"),
    "activity": ("06-recording-queue", "1440x900"),
    "quick-capture": ("10-quick-capture", "520x560"),
}


def run(locale: str, name: str, story: str, size: str, timeout: float = 20) -> Path | None:
    lang, apple_locale = LOCALES[locale]
    seed = json.dumps(json.loads((SEED / f"{locale}.json").read_text()), ensure_ascii=False)
    dest = OUT / locale / "mac" / f"{name}.png"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.unlink(missing_ok=True)
    shot = SANDBOX_TMP / f"store-{locale}-{name}.png"
    shot.unlink(missing_ok=True)
    proc = subprocess.Popen([
        str(APP), "-AppleLanguages", f"({lang})", "-AppleLocale", apple_locale,
        "--disable-release-notes", "--debug-seed-signal-fixtures", "-VoxScreenshotUnlocked",
        "-VoxSeedSamples", seed, "--localization-screenshot", story,
        "--localization-screenshot-size", size, "--localization-screenshot-output", str(shot),
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if shot.exists() and shot.stat().st_size > 0:
                time.sleep(0.3)  # let the atomic write settle
                shot.replace(dest)
                return dest
            if proc.poll() is not None:
                return None
            time.sleep(0.2)
        return None
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--locale")
    parser.add_argument("--only")
    args = parser.parse_args()
    locales = args.locale.split(",") if args.locale else list(LOCALES)
    names = args.only.split(",") if args.only else list(STORIES)
    for locale in locales:
        # First launch seeds (or renames) the routes and draft in this language.
        run(locale, "_warmup", "01-capture", "1440x900")
        (OUT / locale / "mac" / "_warmup.png").unlink(missing_ok=True)
        results = []
        for name in names:
            story, size = STORIES[name]
            results.append(f"{name}:{'ok' if run(locale, name, story, size) else 'FAILED'}")
        print(locale, " ".join(results), flush=True)


if __name__ == "__main__":
    main()
