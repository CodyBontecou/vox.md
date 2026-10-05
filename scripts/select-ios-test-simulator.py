#!/usr/bin/env python3
"""Select an available iPhone on the selected Xcode's iOS simulator SDK."""

import json
import re
import subprocess
import sys


# Older runtimes crash in Swift TaskLocal::StopLookupScope when synchronous
# XCTest/SwiftUI code releases a default-main-actor object (vox.md #22).
# https://github.com/swiftlang/swift/issues/88036
MINIMUM_RUNTIME = (26, 4, 0)
PREFERRED_IPHONES = (
    "iPhone 17 Pro", "iPhone 17", "iPhone 16 Pro", "iPhone 16", "iPhone 15 Pro", "iPhone 15",
)


def version_tuple(value):
    if not re.fullmatch(r"\d+(?:\.\d+){0,2}", value):
        raise ValueError(f"Invalid simulator SDK/runtime version: {value!r}")
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * (3 - len(parts))


def select_simulator(payload, sdk):
    sdk_version = version_tuple(sdk)
    if sdk_version < MINIMUM_RUNTIME:
        raise ValueError("Apple CI requires iOS 26.4+ for the fixed Swift concurrency runtime")

    candidates = []
    for runtime in payload["runtimes"]:
        identifier = runtime["identifier"]
        if not identifier.startswith("com.apple.CoreSimulator.SimRuntime.iOS-"):
            continue
        if not runtime.get("isAvailable", False):
            continue
        version = version_tuple(runtime["version"])
        if version[:2] != sdk_version[:2] or version < MINIMUM_RUNTIME:
            continue
        for device in payload["devices"].get(identifier, []):
            if not device.get("isAvailable", False) or not device["name"].startswith("iPhone"):
                continue
            name = device["name"]
            preference = PREFERRED_IPHONES.index(name) if name in PREFERRED_IPHONES else len(PREFERRED_IPHONES)
            candidates.append((tuple(-part for part in version), preference, name, device["udid"], runtime))

    if not candidates:
        raise ValueError(
            f"No available iPhone on the iOS {sdk_version[0]}.{sdk_version[1]} runtime "
            f"matching simulator SDK {sdk}. Install that runtime; refusing an older/beta fallback."
        )
    _, _, name, udid, runtime = min(candidates, key=lambda item: item[:4])
    return name, udid, runtime["version"]


def main():
    try:
        sdk = subprocess.check_output(
            ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"],
            text=True, timeout=30,
        ).strip()
        payload = json.loads(subprocess.check_output(
            ["xcrun", "simctl", "list", "--json"], text=True, timeout=30,
        ))
        name, udid, version = select_simulator(payload, sdk)
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError) as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    print(f"Using simulator: {name} ({udid}), iOS {version}, simulator SDK {sdk}", file=sys.stderr)
    print(f"destination=platform=iOS Simulator,id={udid}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
