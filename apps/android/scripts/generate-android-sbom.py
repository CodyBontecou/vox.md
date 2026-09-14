#!/usr/bin/env python3
"""Generate a deterministic CycloneDX inventory from Android and Rust lockfiles."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from urllib.parse import quote


ANDROID_ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = ANDROID_ROOT.parents[1]
OUTPUT = REPOSITORY_ROOT / "artifacts" / "android-release" / "vox-android-sbom.cdx.json"
ANDROID_MODULES = ("app", "capture-domain", "core-bridge", "data", "platform-services", "wear")


def maven_components() -> list[dict]:
    coordinates: dict[tuple[str, str, str], set[str]] = {}
    for module in ANDROID_MODULES:
        lockfile = ANDROID_ROOT / module / "gradle.lockfile"
        if not lockfile.is_file():
            raise ValueError(f"missing Android dependency lock: {lockfile}")
        for raw_line in lockfile.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            coordinate, configurations = line.split("=", 1)
            if "releaseRuntimeClasspath" not in configurations.split(","):
                continue
            parts = coordinate.split(":")
            if len(parts) != 3:
                raise ValueError(f"unexpected locked Maven coordinate: {coordinate}")
            key = (parts[0], parts[1], parts[2])
            coordinates.setdefault(key, set()).add(module)

    result = []
    for (group, name, version), modules in sorted(coordinates.items()):
        purl = f"pkg:maven/{quote(group, safe='')}/{quote(name, safe='')}@{quote(version, safe='')}"
        result.append(
            {
                "type": "library",
                "bom-ref": purl,
                "group": group,
                "name": name,
                "version": version,
                "purl": purl,
                "properties": [
                    {"name": "vox.android.modules", "value": ",".join(sorted(modules))},
                ],
            },
        )
    return result


def cargo_components() -> list[dict]:
    lockfile = REPOSITORY_ROOT / "Packages" / "vox-core-rust" / "Cargo.lock"
    if not lockfile.is_file():
        raise ValueError(f"missing Rust dependency lock: {lockfile}")
    packages = []
    current = None
    for raw_line in lockfile.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if line == "[[package]]":
            if current is not None:
                packages.append(current)
            current = {}
            continue
        if current is None or "=" not in line:
            continue
        key, raw_value = (part.strip() for part in line.split("=", 1))
        if key in {"name", "version", "checksum"}:
            value = json.loads(raw_value)
            if not isinstance(value, str):
                raise ValueError(f"Cargo.lock {key} is not a string")
            current[key] = value
    if current is not None:
        packages.append(current)
    result = []
    for package in packages:
        name = package.get("name")
        version = package.get("version")
        if not isinstance(name, str) or not isinstance(version, str):
            raise ValueError("Cargo.lock package is missing a name or version")
        purl = f"pkg:cargo/{quote(name, safe='')}@{quote(version, safe='')}"
        component = {
            "type": "library",
            "bom-ref": purl,
            "name": name,
            "version": version,
            "purl": purl,
            "properties": [
                {"name": "vox.android.modules", "value": "core-bridge"},
            ],
        }
        checksum = package.get("checksum")
        if isinstance(checksum, str):
            component["hashes"] = [{"alg": "SHA-256", "content": checksum}]
        result.append(component)
    return sorted(result, key=lambda item: item["bom-ref"])


def render() -> str:
    components = maven_components() + cargo_components()
    references = [component["bom-ref"] for component in components]
    if len(references) != len(set(references)):
        duplicates = sorted(reference for reference in set(references) if references.count(reference) > 1)
        raise ValueError(f"duplicate SBOM references: {duplicates}")
    document = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "version": 1,
        "metadata": {
            "component": {
                "type": "application",
                "bom-ref": "pkg:generic/vox.md-android@0.1.0-foundation",
                "name": "Vox.md Android and Wear",
                "version": "0.1.0-foundation",
            },
            "properties": [
                {"name": "vox.sbom.inputs", "value": "Gradle releaseRuntimeClasspath locks and Cargo.lock"},
                {"name": "vox.sbom.networkContent", "value": "none"},
            ],
        },
        "components": sorted(components, key=lambda item: item["bom-ref"]),
    }
    return json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--output", type=Path, default=OUTPUT)
    arguments = parser.parse_args()
    try:
        encoded = render()
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Android SBOM generation failed: {error}", file=sys.stderr)
        return 1
    if arguments.check:
        if not arguments.output.is_file() or arguments.output.read_text(encoding="utf-8") != encoded:
            print("Android SBOM is missing or stale; run generate-android-sbom.py", file=sys.stderr)
            return 1
    else:
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        arguments.output.write_text(encoded, encoding="utf-8")
    count = len(json.loads(encoded)["components"])
    print(f"Android SBOM {'verified' if arguments.check else 'generated'}: {count} locked components")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
