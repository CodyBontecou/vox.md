#!/usr/bin/env python3
"""Capture the Mac app's store screens for every locale (DEBUG build).

    python3 scripts/localization/store-screenshots/capture_mac.py [--locale ja,de-DE] [--only workspace,activity]

Build first: xcodebuild build -project Voxboard.xcodeproj -scheme "Voxboard Mac" -configuration Debug
-destination 'platform=macOS' -derivedDataPath build/DerivedData-macOS

The Debug app shares the sandbox container and app group with any Vox.md installed on this Mac,
and each locale starts from a wiped container. So the script backs both up to
build/mac-store-capture-backup/ first and restores them when it finishes (also on Ctrl-C).

Windows are captured with `screencapture -l` (the app's own --localization-screenshot-output hook
renders the sidebar blank) in light mode at 1440×900, with the sidebar widened to 236pt so route
names aren't truncated:
  - workspace, activity: the real main window, opened on that destination; resized and the sidebar
    splitter set through accessibility, then captured inactive (Finder is activated first).
  - library: the screenshot-story window (fixture history with a delivered entry selected). Its
    splitter isn't exposed to accessibility, so the divider is dragged with a synthetic mouse drag:
    the pointer moves briefly inside that window.
  - quick-capture: the app's own hook (no sidebar), written to the sandbox tmp dir.

Needs Accessibility and Screen Recording permission for the terminal. Output:
artifacts/localization/store-signal-captures/<locale>/mac/<name>.png; then run
normalize_captures.py and render.mjs --only mac.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
APP = REPO / "build/DerivedData-macOS/Build/Products/Debug/Vox.md.app/Contents/MacOS/Vox.md"
OUT = REPO / "artifacts/localization/store-signal-captures"
SEED = HERE / "strings" / "seed"
TOOLS = REPO / "build/store-screenshot-tools"
BACKUP = REPO / "build/mac-store-capture-backup"
GROUP = Path.home() / "Library/Group Containers/group.bontecou.Voxboard"
CONTAINER = Path.home() / "Library/Containers/bontecou.Voxboard"
DATA = CONTAINER / "Data"
SANDBOX_TMP = DATA / "tmp"  # the sandboxed app can only write inside its container

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
# name -> (story, story window size)
STORIES = {
    "workspace": ("01-capture", "1440x900"),
    "library": ("02-history", "1440x900"),
    "activity": ("06-recording-queue", "1440x900"),
    "quick-capture": ("10-quick-capture", "520x560"),
}
MAIN_WINDOW = {"workspace", "activity"}
SIDEBAR = 236
STORY_SIDEBAR = 144  # where the story window's sidebar divider starts


def build_tools() -> None:
    TOOLS.mkdir(parents=True, exist_ok=True)
    for name in ("winid", "drag"):
        src, binary = HERE / "mac-tools" / f"{name}.swift", TOOLS / name
        if not binary.exists() or binary.stat().st_mtime < src.stat().st_mtime:
            subprocess.run(["swiftc", "-O", str(src), "-o", str(binary)], check=True)


def backup() -> None:
    if BACKUP.exists():
        raise SystemExit(f"{BACKUP} exists: a previous run didn't restore. Restore or remove it first.")
    BACKUP.mkdir(parents=True)
    for src, name in ((GROUP, "group"), (CONTAINER, "container")):
        if src.exists():
            subprocess.run(["ditto", str(src), str(BACKUP / name)], check=True)


def restore() -> None:
    for dest, name in ((GROUP, "group"), (CONTAINER, "container")):
        if (BACKUP / name).exists():
            subprocess.run(["rsync", "-a", "--delete", f"{BACKUP / name}/", f"{dest}/"], check=True)
    shutil.rmtree(BACKUP)


def reset() -> None:
    """Same wipe as the iOS -VoxScreenshotReset: app group data, shared defaults, local vault."""
    for item in GROUP.iterdir() if GROUP.exists() else []:
        if item.name != "Library" and not item.name.startswith("."):
            shutil.rmtree(item) if item.is_dir() else item.unlink()
    shutil.rmtree(DATA / "Documents/Vox Notes", ignore_errors=True)
    for plist in (GROUP / "Library/Preferences/group.bontecou.Voxboard", DATA / "Library/Preferences/bontecou.Voxboard"):
        subprocess.run(["defaults", "delete", str(plist)], capture_output=True)


def osa(pid: int, script: str) -> str:
    full = f'tell application "System Events" to tell (first process whose unix id is {pid})\n{script}\nend tell'
    return subprocess.run(["osascript", "-e", full], capture_output=True, text=True).stdout.strip()


def run(locale: str, name: str, story: str, size: str, wait: float = 6.0) -> str | None:
    lang, apple_locale = LOCALES[locale]
    seed = json.dumps(json.loads((SEED / f"{locale}.json").read_text()), ensure_ascii=False)
    dest = OUT / locale / "mac" / f"{name}.png"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.unlink(missing_ok=True)
    hook_shot = SANDBOX_TMP / f"store-{locale}-{name}.png"
    hook_shot.unlink(missing_ok=True)
    args = [
        str(APP), "-AppleLanguages", f"({lang})", "-AppleLocale", apple_locale,
        "--disable-release-notes", "--debug-seed-signal-fixtures", "-VoxScreenshotUnlocked",
        "--debug-appearance=light", "-VoxSeedSamples", seed, "--localization-screenshot", story,
        # Main-window captures keep the extra story window small so it isn't the largest window.
        "--localization-screenshot-size", "500x300" if name in MAIN_WINDOW else size,
    ]
    if name == "quick-capture":
        args += ["--localization-screenshot-output", str(hook_shot)]
    proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(wait)
        if name == "quick-capture":
            for _ in range(20):
                if hook_shot.exists() and hook_shot.stat().st_size > 0:
                    time.sleep(0.3)
                    hook_shot.replace(dest)
                    return "hook"
                time.sleep(0.3)
            return None
        if name in MAIN_WINDOW:
            osa(proc.pid, f"""repeat with w in windows
  if item 1 of (size of w as list) > 700 then
    set position of w to {{20, 40}}
    set size of w to {{1440, 900}}
    delay 1
    set value of (first UI element of splitter group 1 of group 1 of w whose role is "AXSplitter") to {SIDEBAR}
  end if
end repeat""")
        else:  # library: story window, titled "Vox.md"
            x, y = (int(v) for v in osa(proc.pid, 'get position of window "Vox.md"').split(", "))
            osa(proc.pid, 'perform action "AXRaise" of window "Vox.md"')
            subprocess.run([str(TOOLS / "drag"), str(x + STORY_SIDEBAR), str(y + 500), str(x + SIDEBAR), str(y + 500)], check=True)
        if name in MAIN_WINDOW:
            # Capture the window inactive, as the store set was: an active main window draws its
            # destination title over the breadcrumb.
            subprocess.run(["osascript", "-e", 'tell application "Finder" to activate'], capture_output=True)
        time.sleep(2)
        out = subprocess.run([str(TOOLS / "winid"), str(proc.pid)], capture_output=True, text=True).stdout.split()
        if len(out) != 2 or out[0] == "0":
            return None
        subprocess.run(["screencapture", "-x", "-o", "-l", out[0], str(dest)], check=True)
        return out[1]
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--locale")
    parser.add_argument("--only")
    args = parser.parse_args()
    locales = args.locale.split(",") if args.locale else list(LOCALES)
    names = args.only.split(",") if args.only else list(STORIES)
    if not APP.exists():
        raise SystemExit(f"Build the Mac Debug app first: {APP}")
    build_tools()
    backup()
    try:
        for locale in locales:
            reset()
            # First launch seeds the localized routes and draft.
            run(locale, "_warmup", "01-capture", "1440x900")
            (OUT / locale / "mac" / "_warmup.png").unlink(missing_ok=True)
            results = [f"{n}:{run(locale, n, *STORIES[n]) or 'FAILED'}" for n in names]
            print(locale, " ".join(results), flush=True)
    finally:
        restore()
        print("restored Vox.md app data", flush=True)


if __name__ == "__main__":
    main()
