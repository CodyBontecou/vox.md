#!/usr/bin/env python3
"""Isolate #22's hosted tests from an arbitrarily selected older Swift runtime."""

import argparse
import json
from pathlib import Path
import subprocess
import sys
import uuid


PREFERRED_NAMES = [
    "iPhone 17 Pro", "iPhone 17", "iPhone 16 Pro", "iPhone 16", "iPhone 15 Pro", "iPhone 15",
]


def version_tuple(value):
    parts = tuple(int(part) for part in value.split("."))
    if not 1 <= len(parts) <= 3:
        raise ValueError(f"Invalid simulator/SDK version: {value}")
    return parts + (0,) * (3 - len(parts))


def select_simulator(sdk_version, runtimes, devices):
    """Require the selected Xcode SDK's runtime; never silently fall back."""
    candidates = []
    for runtime in runtimes:
        identifier = runtime.get("identifier", "")
        if not identifier.startswith("com.apple.CoreSimulator.SimRuntime.iOS-"):
            continue
        if not runtime.get("isAvailable"):
            continue
        if version_tuple(runtime["version"]) != version_tuple(sdk_version):
            continue
        for device in devices.get(identifier, []):
            name = device.get("name", "")
            if not device.get("isAvailable") or not name.startswith("iPhone"):
                continue
            # Reject malformed destinations rather than pass them to xcodebuild.
            uuid.UUID(device["udid"])
            rank = PREFERRED_NAMES.index(name) if name in PREFERRED_NAMES else len(PREFERRED_NAMES)
            candidates.append((rank, device["udid"], runtime, device))
    if not candidates:
        raise ValueError(
            f"No available iPhone simulator for the selected iOS SDK {sdk_version}; "
            "refusing an older or beta runtime fallback (Refs #22)."
        )
    _, _, runtime, device = min(candidates, key=lambda candidate: candidate[:2])
    return {
        "sdk_version": sdk_version,
        "runtime": {key: runtime.get(key) for key in ("identifier", "version", "buildversion")},
        "device": {key: device.get(key) for key in ("name", "udid", "deviceTypeIdentifier")},
        "destination": f"platform=iOS Simulator,id={device['udid']}",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--github-output", required=True, type=Path)
    parser.add_argument("--metadata", required=True, type=Path)
    args = parser.parse_args()
    metadata = {}
    try:
        sdk = subprocess.check_output(
            ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], text=True
        ).strip()
        runtimes = json.loads(subprocess.check_output(
            ["xcrun", "simctl", "list", "runtimes", "--json"], text=True
        ))["runtimes"]
        devices = json.loads(subprocess.check_output(
            ["xcrun", "simctl", "list", "devices", "available", "--json"], text=True
        ))["devices"]
        metadata = {"sdk_version": sdk, "available_runtimes": runtimes}
        selected = select_simulator(sdk, runtimes, devices)
        metadata["selected"] = selected
        with args.github_output.open("a") as output:
            output.write(f"destination={selected['destination']}\n")
        print(f"Using SDK-matched simulator: {json.dumps(selected, sort_keys=True)}")
        return 0
    except (ValueError, KeyError, subprocess.CalledProcessError, OSError) as error:
        metadata["error"] = str(error)
        print(f"::error::{error}", file=sys.stderr)
        return 1
    finally:
        args.metadata.parent.mkdir(parents=True, exist_ok=True)
        args.metadata.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    sys.exit(main())
