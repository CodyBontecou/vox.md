#!/usr/bin/env python3
"""Fail when phone-only inference or Markdown runtimes leak into Wear artifacts."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
from zipfile import ZipFile


FORBIDDEN = (
    "libvosk.so",
    "libvox_core_uniffi.so",
    "libmlkit_google_ocr_pipeline.so",
    "libmlkitcommonpipeline.so",
    "libonnxruntime.so",
    "libsherpa-onnx-c-api.so",
    "libsherpa-onnx-cxx-api.so",
    "libsherpa-onnx-jni.so",
    "assets/mlkit-google-ocr-models/",
    "assets/mlkit_label_default_model/",
)

FORBIDDEN_DEX_MARKERS = (
    b"Lorg/vosk/",
    b"Lcom/k2fsa/sherpa/onnx/",
    b"Lmd/vox/android/platformservices/LocalLiveSpeechSession;",
    b"Lmd/vox/android/platformservices/SpeechModelManager;",
    b"Lcom/google/mlkit/vision/text/",
    b"Lcom/google/mlkit/vision/label/",
)

GEIST_FONTS = {
    "geist_regular.ttf": "5c8968eafb98a4c4f47033daf29e38e284a6f2a82eb017d171ab040fe7c4b615",
    "geist_medium.ttf": "0090e004725f6f64b841715b4167920580f883fcf9b67fc6d744089103fec101",
    "geist_semibold.ttf": "612ec98df33935354f39e81e54101656961ab6e5549f64b63eb57868ba7bab8d",
    "geist_mono_regular.ttf": "42d8ad2e610238e64e8abfcde3037c63f7850a73928742b7ab7229d897bcb155",
    "geist_mono_medium.ttf": "90b15711dc3779b2e64e8aff5228154dd019a90bce4947549c4a8a8a43f2ac25",
}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument(
        "--scan-dex",
        action="store_true",
        help="also reject dormant phone-only type references in optimized DEX files",
    )
    args = parser.parse_args()
    if not args.apk.is_file():
        raise SystemExit(f"missing Wear artifact: {args.apk}")
    with ZipFile(args.apk) as archive:
        entries = archive.namelist()
        prefix = "base/" if args.apk.suffix == ".aab" else ""
        for packaged_name, expected_sha256 in GEIST_FONTS.items():
            entry = f"{prefix}res/font/{packaged_name}"
            if entry not in entries:
                raise SystemExit(f"Wear artifact is missing packaged Geist font: {entry}")
            actual_sha256 = hashlib.sha256(archive.read(entry)).hexdigest()
            if actual_sha256 != expected_sha256:
                raise SystemExit(f"Wear packaged Geist font hash differs: {packaged_name}")
        dex_leaks = []
        if args.scan_dex:
            for entry in entries:
                if not entry.endswith(".dex"):
                    continue
                contents = archive.read(entry)
                dex_leaks.extend(
                    f"{entry}: {marker.decode()}"
                    for marker in FORBIDDEN_DEX_MARKERS
                    if marker in contents
                )
    leaked = sorted(entry for entry in entries if any(marker in entry for marker in FORBIDDEN))
    if leaked or dex_leaks:
        raise SystemExit(
            "phone-only runtime leaked into Wear artifact:\n"
            + "\n".join(sorted(leaked + dex_leaks))
        )
    print(
        "Wear artifact validation passed: exact Geist fonts are packaged, and phone-only "
        "Rust, ASR, OCR, and image-labeling runtimes are absent."
    )


if __name__ == "__main__":
    main()
