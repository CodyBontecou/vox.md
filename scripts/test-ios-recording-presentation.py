#!/usr/bin/env python3
"""Check the expanded Record Audio action's native Shortcuts presentation.

Observe only: never launches apps, creates/edits shortcuts, or executes recording.
Stage an owned disposable Record Audio action in Shortcuts, expand it, and pass
--device explicitly. --capture replays a saved Argent describe JSON receipt;
that checks the captured screen, not the current installed app. English UI only.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

PREFIX = "editor.action.bontecou.Voxboard.OpenVoxboardRecordIntent."


def check(receipt: dict) -> None:
    description = receipt.get("description")
    if not isinstance(description, str):
        raise ValueError("No trustworthy Argent description; presentation is unknown")
    system_row = f'id="{PREFIX}OpenWhenRun"'
    custom_row = f'id="{PREFIX}openApp"'
    if description.count('AXButton "Action Options"') != 1:
        raise ValueError("Stage exactly one expanded primary Record Audio action in Shortcuts")
    if PREFIX in description:
        # The physical-device tree carries the primary action's parameter IDs.
        if description.count(system_row) != 1:
            raise ValueError("Expected exactly one primary Record Audio action")
        if custom_row in description:
            raise ValueError("Duplicate foreground controls: Open App AND Open When Run")
    elif receipt.get("source") == "ax-service":
        # Simulator AX omits the parameter IDs. This is a presentation check of
        # an explicitly staged action, not proof of its app identity or binding.
        summaries = re.findall(r'AXGroup "(?:Start|Stop|Start or Stop),  recording with , Preset"', description)
        if len(summaries) != 1 or description.count('AXButton "Open When Run"') != 1:
            raise ValueError("Stage exactly one expanded primary Record Audio action in Shortcuts")
        if '"Open App"' in description:
            raise ValueError("Duplicate foreground controls: Open App AND Open When Run")
    else:
        raise ValueError("No primary action parameter IDs; presentation is unknown")
    if '"Open When Run"' not in description:
        raise ValueError("Native Open When Run control has no visible label")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--device", help="Explicit physical iPhone UDID or iOS simulator UDID")
    source.add_argument("--capture", type=Path, help="Saved Argent describe JSON (not a live check)")
    parser.add_argument("--output", type=Path, help="Save a fresh observation receipt")
    args = parser.parse_args()
    try:
        if args.capture:
            receipt = json.loads(args.capture.read_text())
        else:
            result = subprocess.run(
                ["argent", "run", "describe", "--udid", args.device, "--json"],
                check=True, capture_output=True, text=True, timeout=150,
            )
            receipt = json.loads(result.stdout)
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(receipt, indent=2) + "\n")
        check(receipt)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print("PASS: expanded Record Audio has only the native Open When Run control"
          + (" (captured evidence only)" if args.capture else " (live)"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
