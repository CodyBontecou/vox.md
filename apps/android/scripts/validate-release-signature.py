#!/usr/bin/env python3
"""Require and cryptographically verify a JAR-signed Android App Bundle."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path
from zipfile import BadZipFile, ZipFile


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: validate-release-signature.py <bundle.aab>")
    bundle = Path(sys.argv[1])
    if not bundle.is_file():
        raise SystemExit(f"missing release bundle: {bundle}")
    try:
        with ZipFile(bundle) as archive:
            upper_names = {name.upper() for name in archive.namelist()}
    except BadZipFile as error:
        raise SystemExit(f"invalid release bundle ZIP: {error}") from error

    signature_blocks = {
        name for name in upper_names
        if name.startswith("META-INF/") and name.endswith((".RSA", ".DSA", ".EC"))
    }
    signature_files = {
        name for name in upper_names
        if name.startswith("META-INF/") and name.endswith(".SF")
    }
    if not signature_blocks or not signature_files:
        raise SystemExit("release bundle is unsigned: JAR signature entries are absent")

    result = subprocess.run(
        ["jarsigner", "-verify", str(bundle)],
        check=False,
        capture_output=True,
        text=True,
    )
    output = result.stdout + result.stderr
    if result.returncode != 0 or "jar verified." not in output.lower():
        raise SystemExit("release bundle signature verification failed")
    print(f"Release signature validation passed: {bundle.name}")


if __name__ == "__main__":
    main()
