#!/usr/bin/env python3
"""Qualify production Vosk inference on a connected Android device with connectivity disabled."""

from __future__ import annotations

import hashlib
import os
from pathlib import Path
import subprocess


ANDROID_ROOT = Path(__file__).resolve().parents[1]
APP_APK = ANDROID_ROOT / "app/build/outputs/apk/debug/app-debug.apk"
TEST_APK = ANDROID_ROOT / "app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk"
PACKAGE = "md.vox.android"
TEST_PACKAGE = "md.vox.android.test"
RUNNER = f"{TEST_PACKAGE}/androidx.test.runner.AndroidJUnitRunner"
TEST = "md.vox.android.LocalSpeechInferenceInstrumentationTest"
MODEL_SHA256 = "30f26242c4eb449f948e42cb302dd7a686cb29a3423a8367f99ff41780942498"
AUDIO_SHA256 = "dcfea5712c43a43ba7ae8083afb39d36993e5a69c46e88b68aaa72b65cb615bb"


def fail(message: str) -> None:
    raise SystemExit(f"Android local-speech qualification failed: {message}")


def run(arguments: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(arguments, check=False, text=True, capture_output=True)
    if check and result.returncode != 0:
        detail = (result.stdout + result.stderr).strip()
        fail(f"{' '.join(arguments[:5])}: {detail or f'exit {result.returncode}'}")
    return result


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def checked_fixture(environment_key: str, expected_hash: str) -> Path:
    raw = os.environ.get(environment_key)
    if not raw:
        fail(f"{environment_key} must name the reviewed local qualification fixture")
    path = Path(raw).expanduser().resolve()
    if not path.is_file():
        fail(f"{environment_key} does not name a file: {path}")
    actual = sha256(path)
    if actual != expected_hash:
        fail(f"{environment_key} SHA-256 mismatch: expected {expected_hash}, observed {actual}")
    return path


def adb(adb_path: Path, serial: str, *arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return run([str(adb_path), "-s", serial, *arguments], check=check)


def stage_fixture(adb_path: Path, serial: str, source: Path, destination_name: str) -> None:
    temporary = f"/data/local/tmp/vox-{destination_name}"
    adb(adb_path, serial, "push", str(source), temporary)
    adb(adb_path, serial, "shell", "chmod", "0644", temporary)
    adb(adb_path, serial, "shell", "run-as", PACKAGE, "mkdir", "-p", "files/local-speech-qualification")
    adb(
        adb_path,
        serial,
        "shell",
        "run-as",
        PACKAGE,
        "cp",
        temporary,
        f"files/local-speech-qualification/{destination_name}",
    )
    adb(adb_path, serial, "shell", "rm", "-f", temporary)


def main() -> None:
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    serial = os.environ.get("ANDROID_SERIAL")
    if not sdk:
        fail("ANDROID_HOME or ANDROID_SDK_ROOT is required")
    if not serial:
        fail("ANDROID_SERIAL is required so no unrelated device can be modified")
    model = checked_fixture("VOX_TEST_VOSK_MODEL_ZIP", MODEL_SHA256)
    audio = checked_fixture("VOX_TEST_SPEECH_WAV", AUDIO_SHA256)
    adb_path = Path(sdk) / "platform-tools/adb"
    if not adb_path.is_file():
        fail(f"adb is missing at {adb_path}")
    if not APP_APK.is_file() or not TEST_APK.is_file():
        fail("debug app/test APKs are missing; run :app:assembleDebug :app:assembleDebugAndroidTest first")
    if adb(adb_path, serial, "get-state").stdout.strip() != "device":
        fail(f"{serial} is not a ready adb device")

    previous_airplane = adb(adb_path, serial, "shell", "settings", "get", "global", "airplane_mode_on").stdout.strip()
    try:
        adb(adb_path, serial, "install", "-r", "-t", str(APP_APK))
        cleared = adb(adb_path, serial, "shell", "pm", "clear", PACKAGE)
        if "Success" not in cleared.stdout:
            fail(f"could not clear the isolated emulator app sandbox: {cleared.stdout.strip()}")
        adb(adb_path, serial, "install", "-r", "-t", str(TEST_APK))
        stage_fixture(adb_path, serial, model, "vosk-model-small-en-us-0.15.zip")
        stage_fixture(adb_path, serial, audio, "vosk-api-test.wav")
        adb(adb_path, serial, "shell", "cmd", "connectivity", "airplane-mode", "enable")
        result = adb(
            adb_path,
            serial,
            "shell",
            "am",
            "instrument",
            "-w",
            "-r",
            "-e",
            "class",
            TEST,
            RUNNER,
        )
        output = result.stdout + result.stderr
        if "OK (2 tests)" not in output or "FAILURES!!!" in output or "Process crashed" in output:
            fail(f"instrumented inference did not pass:\n{output.strip()}")
    finally:
        adb(adb_path, serial, "shell", "pm", "clear", PACKAGE, check=False)
        mode = "enable" if previous_airplane == "1" else "disable"
        adb(adb_path, serial, "shell", "cmd", "connectivity", "airplane-mode", mode, check=False)

    print("Android local-speech qualification passed: exact-hash real speech completed offline and the frozen Wear preset delivered verified Markdown.")


if __name__ == "__main__":
    main()
