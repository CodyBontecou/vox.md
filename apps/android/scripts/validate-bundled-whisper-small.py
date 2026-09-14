#!/usr/bin/env python3
"""Verify the source and release-bundle copies of Android's default speech model."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
from pathlib import Path
import zipfile


def load_provisioner():
    path = Path(__file__).with_name("provision-bundled-whisper-small.py")
    spec = importlib.util.spec_from_file_location("vox_whisper_small_provisioner", path)
    if spec is None or spec.loader is None:
        fail(f"could not load provisioner: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def stream_digest(source) -> str:
    digest = hashlib.sha256()
    while chunk := source.read(1024 * 1024):
        digest.update(chunk)
    return digest.hexdigest()


def fail(message: str) -> None:
    raise SystemExit(f"Bundled Whisper Small validation failed: {message}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--assets", type=Path, required=True)
    parser.add_argument("--bundle", type=Path, required=True)
    arguments = parser.parse_args()
    provisioner = load_provisioner()
    assets = arguments.assets.resolve()
    bundle = arguments.bundle.resolve()

    if not bundle.is_file():
        fail(f"release bundle is missing: {bundle}")

    expected_receipt = (
        "version=2\n"
        f"id={provisioner.MODEL_ID}\n"
        f"engine={provisioner.ENGINE}\n"
        f"manifestSha256={provisioner.manifest_sha256()}\n"
    ).encode("utf-8")
    for name, expected_bytes, expected_sha256 in provisioner.FILES:
        source = assets / name
        if not provisioner.valid(source, expected_bytes, expected_sha256):
            fail(f"source asset is missing or invalid: {name}")
    if (assets / provisioner.RECEIPT).read_bytes() != expected_receipt:
        fail("source receipt is missing or invalid")

    prefix = f"whisper_small/assets/speech-models/{provisioner.MODEL_ID}/"
    with zipfile.ZipFile(bundle) as archive:
        for name, expected_bytes, expected_sha256 in provisioner.FILES:
            entry = prefix + name
            try:
                info = archive.getinfo(entry)
            except KeyError:
                fail(f"bundle entry is missing: {entry}")
            if info.file_size != expected_bytes:
                fail(f"bundle entry has the wrong size: {entry}")
            with archive.open(info) as source:
                if stream_digest(source) != expected_sha256:
                    fail(f"bundle entry has the wrong SHA-256: {entry}")
        receipt_entry = prefix + provisioner.RECEIPT
        try:
            bundled_receipt = archive.read(receipt_entry)
        except KeyError:
            fail(f"bundle receipt is missing: {receipt_entry}")
        if bundled_receipt != expected_receipt:
            fail("bundle receipt differs from the pinned manifest")

    print("Bundled Whisper Small validation passed: exact source assets and release AI-pack entries are present.")


if __name__ == "__main__":
    main()
