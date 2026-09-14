#!/usr/bin/env python3
"""Download one pinned named model, then prove production inference with connectivity off."""

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
TEST_CLASS = "md.vox.android.NamedModelInferenceInstrumentationTest"
AUDIO_SHA256 = "dcfea5712c43a43ba7ae8083afb39d36993e5a69c46e88b68aaa72b65cb615bb"
MODEL_IDS = {
    "parakeet-v2",
    "parakeet-v3",
    "ggml-tiny",
    "ggml-base",
    "ggml-small",
    "ggml-medium",
    "ggml-large-v3-turbo",
}


def fail(message: str) -> None:
    raise SystemExit(f"Android named-model qualification failed: {message}")


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


def adb(adb_path: Path, serial: str, *arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return run([str(adb_path), "-s", serial, *arguments], check=check)


def stage_audio(adb_path: Path, serial: str, source: Path) -> None:
    temporary = "/data/local/tmp/vox-named-model-speech.wav"
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
        "files/local-speech-qualification/vosk-api-test.wav",
    )
    adb(adb_path, serial, "shell", "rm", "-f", temporary)


def run_test(adb_path: Path, serial: str, method: str, model_id: str) -> None:
    result = adb(
        adb_path,
        serial,
        "shell",
        "am",
        "instrument",
        "-w",
        "-r",
        "-e",
        "voxModelID",
        model_id,
        "-e",
        "class",
        f"{TEST_CLASS}#{method}",
        RUNNER,
    )
    output = result.stdout + result.stderr
    if "OK (1 test)" not in output or "FAILURES!!!" in output or "Process crashed" in output:
        fail(f"{method} did not pass:\n{output.strip()}")


def main() -> None:
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    serial = os.environ.get("ANDROID_SERIAL")
    model_id = os.environ.get("VOX_TEST_NAMED_MODEL_ID")
    audio_raw = os.environ.get("VOX_TEST_SPEECH_WAV")
    if not sdk or not serial:
        fail("ANDROID_HOME and ANDROID_SERIAL are required")
    if model_id not in MODEL_IDS:
        fail(f"VOX_TEST_NAMED_MODEL_ID must be one of {sorted(MODEL_IDS)}")
    if not audio_raw:
        fail("VOX_TEST_SPEECH_WAV must name the reviewed speech fixture")
    audio = Path(audio_raw).expanduser().resolve()
    if not audio.is_file() or sha256(audio) != AUDIO_SHA256:
        fail("VOX_TEST_SPEECH_WAV is missing or its SHA-256 differs")
    adb_path = Path(sdk) / "platform-tools/adb"
    if not adb_path.is_file() or not APP_APK.is_file() or not TEST_APK.is_file():
        fail("adb or assembled debug app/test APKs are missing")
    if adb(adb_path, serial, "get-state").stdout.strip() != "device":
        fail(f"{serial} is not a ready adb device")

    previous_airplane = adb(adb_path, serial, "shell", "settings", "get", "global", "airplane_mode_on").stdout.strip()
    try:
        adb(adb_path, serial, "install", "-r", "-t", str(APP_APK))
        cleared = adb(adb_path, serial, "shell", "pm", "clear", PACKAGE)
        if "Success" not in cleared.stdout:
            fail(f"could not clear the isolated emulator app sandbox: {cleared.stdout.strip()}")
        adb(adb_path, serial, "install", "-r", "-t", str(TEST_APK))
        stage_audio(adb_path, serial, audio)
        adb(adb_path, serial, "shell", "cmd", "connectivity", "airplane-mode", "disable")
        run_test(adb_path, serial, "downloadsVerifiesInstallsAndSelectsRequestedModel", model_id)
        adb(adb_path, serial, "shell", "cmd", "connectivity", "airplane-mode", "enable")
        run_test(
            adb_path,
            serial,
            "selectedRequestedModelTranscribesRealSpeechOfflineThroughProductionClient",
            model_id,
        )
    finally:
        adb(adb_path, serial, "shell", "pm", "clear", PACKAGE, check=False)
        mode = "enable" if previous_airplane == "1" else "disable"
        adb(adb_path, serial, "shell", "cmd", "connectivity", "airplane-mode", mode, check=False)

    print(f"Android named-model qualification passed: {model_id} downloaded, verified, selected, and transcribed real speech offline.")


if __name__ == "__main__":
    main()
