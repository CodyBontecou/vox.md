#!/usr/bin/env python3
"""Provision Vox.md's integrity-pinned, install-time Android Whisper Small pack."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import shutil
import tempfile
import urllib.request


REPOSITORY = "csukuangfj/sherpa-onnx-whisper-small"
REVISION = "8f3c18b358db4d1f2fc1eae49d75cd20989e4309"
MODEL_ID = "ggml-small"
ENGINE = "SHERPA_WHISPER"
FILES = (
    ("small-encoder.int8.onnx", 112_442_483, "4cbe7b22fa9026b843b60a68640c747de05bafb1a11b57edc0e66c232d9f33a9"),
    ("small-decoder.int8.onnx", 262_226_114, "acad50b5c782696e91b55914cc5ab4f756f1532f76e22aa6fc615f39fb69a8ee"),
    ("small-tokens.txt", 816_730, "b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126"),
)
RECEIPT = "vox-model.properties"


def digest(path: Path) -> str:
    sha256 = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            sha256.update(chunk)
    return sha256.hexdigest()


def valid(path: Path, expected_bytes: int, expected_sha256: str) -> bool:
    return path.is_file() and path.stat().st_size == expected_bytes and digest(path) == expected_sha256


def download(name: str, target: Path, expected_bytes: int, expected_sha256: str) -> None:
    url = f"https://huggingface.co/{REPOSITORY}/resolve/{REVISION}/{name}"
    print(f"Provisioning {name} ({expected_bytes / 1_000_000:.1f} MB)")
    with tempfile.NamedTemporaryFile(dir=target.parent, prefix=f".{name}.", delete=False) as temporary:
        temporary_path = Path(temporary.name)
        request = urllib.request.Request(url, headers={"User-Agent": "Vox.md Android build"})
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                shutil.copyfileobj(response, temporary, length=1024 * 1024)
            temporary.flush()
        except BaseException:
            temporary_path.unlink(missing_ok=True)
            raise
    if not valid(temporary_path, expected_bytes, expected_sha256):
        temporary_path.unlink(missing_ok=True)
        raise SystemExit(f"Downloaded {name} did not match its pinned size and SHA-256")
    temporary_path.replace(target)


def manifest_sha256() -> str:
    manifest = "\n".join(f"{name}:{size}:{sha256}" for name, size, sha256 in FILES)
    return hashlib.sha256(manifest.encode("utf-8")).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    output = arguments.output.resolve()
    output.mkdir(parents=True, exist_ok=True)

    missing = []
    for name, expected_bytes, expected_sha256 in FILES:
        target = output / name
        if valid(target, expected_bytes, expected_sha256):
            continue
        if arguments.check:
            missing.append(name)
        else:
            target.unlink(missing_ok=True)
            download(name, target, expected_bytes, expected_sha256)

    if missing:
        raise SystemExit("Bundled Whisper Small assets are missing or invalid: " + ", ".join(missing))

    receipt = (
        "version=2\n"
        f"id={MODEL_ID}\n"
        f"engine={ENGINE}\n"
        f"manifestSha256={manifest_sha256()}\n"
    )
    receipt_path = output / RECEIPT
    if arguments.check:
        if not receipt_path.is_file() or receipt_path.read_text(encoding="utf-8") != receipt:
            raise SystemExit("Bundled Whisper Small receipt is missing or invalid")
    else:
        receipt_path.write_text(receipt, encoding="utf-8")

    print(f"Bundled Whisper Small is ready at {output}")


if __name__ == "__main__":
    main()
