#!/usr/bin/env python3
"""Run the Android free-quota qualification across a real uninstall/reinstall boundary."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys


ANDROID_ROOT = Path(__file__).resolve().parents[1]
APK = ANDROID_ROOT / "data/build/outputs/apk/androidTest/debug/data-debug-androidTest.apk"
PACKAGE = "md.vox.android.data.test"
RUNNER = f"{PACKAGE}/androidx.test.runner.AndroidJUnitRunner"
TEST_CLASS = "md.vox.android.data.ReinstallAdjustmentInstrumentationTest"


def fail(message: str) -> None:
    raise SystemExit(f"Android reinstall qualification failed: {message}")


def run(arguments: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(arguments, check=False, text=True, capture_output=True)
    if check and result.returncode != 0:
        detail = (result.stdout + result.stderr).strip()
        fail(f"{' '.join(arguments[:4])}: {detail or f'exit {result.returncode}'}")
    return result


def instrument(adb: Path, serial: str, method: str) -> None:
    result = run(
        [
            str(adb),
            "-s",
            serial,
            "shell",
            "am",
            "instrument",
            "-w",
            "-r",
            "-e",
            "class",
            f"{TEST_CLASS}#{method}",
            RUNNER,
        ]
    )
    output = result.stdout + result.stderr
    if "OK (1 test)" not in output or "FAILURES!!!" in output or "Process crashed" in output:
        fail(f"{method} did not pass:\n{output.strip()}")


def uninstall(adb: Path, serial: str) -> None:
    present = run([str(adb), "-s", serial, "shell", "pm", "path", PACKAGE], check=False)
    if not (present.stdout + present.stderr).strip():
        return
    result = run([str(adb), "-s", serial, "uninstall", PACKAGE], check=False)
    output = result.stdout + result.stderr
    if result.returncode != 0 or "Success" not in output:
        fail(f"could not uninstall the exact fixture package: {output.strip()}")


def install(adb: Path, serial: str) -> None:
    result = run([str(adb), "-s", serial, "install", "-t", str(APK)])
    if "Success" not in result.stdout:
        fail(f"fixture installation did not report success: {(result.stdout + result.stderr).strip()}")


def main() -> None:
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    serial = os.environ.get("ANDROID_SERIAL")
    if not sdk:
        fail("ANDROID_HOME or ANDROID_SDK_ROOT is required")
    if not serial:
        fail("ANDROID_SERIAL is required so no unrelated device can be modified")
    adb = Path(sdk) / "platform-tools/adb"
    if not adb.is_file():
        fail(f"adb is missing at {adb}")
    if not APK.is_file():
        fail(f"test APK is missing at {APK}; run :data:assembleDebugAndroidTest first")
    if run([str(adb), "-s", serial, "get-state"]).stdout.strip() != "device":
        fail(f"{serial} is not a ready adb device")

    uninstall(adb, serial)
    try:
        install(adb, serial)
        instrument(adb, serial, "seedExhaustedFreeQuotaBeforeUninstall")
        uninstall(adb, serial)
        install(adb, serial)
        instrument(adb, serial, "freshInstallHasNewIdentityAndEmptyFreeQuota")
    finally:
        uninstall(adb, serial)

    print("Android reinstall qualification passed: 2 phases across an actual package uninstall/reinstall boundary.")


if __name__ == "__main__":
    main()
