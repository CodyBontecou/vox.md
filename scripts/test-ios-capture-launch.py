#!/usr/bin/env python3
"""Build, install and repeatedly cold-launch Vox.md on an explicitly chosen iPhone.

No debugger/test injection, console attachment, screenshots, taps, uninstall, or
user-data reset. The app's normal launch effects still run. Save pending work first.
Success means the exact launched PID/executable survived every sample, not merely
that SpringBoard accepted a launch request. This is a crash smoke test, not a UI
responsiveness test; use QuickCaptureRenderingTests for render assertions.
"""
from __future__ import annotations

import argparse
import json
import math
import plistlib
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[1]


class SmokeFailure(RuntimeError):
    pass


class Device:
    def __init__(self, identifier: str, artifacts: Path):
        self.identifier = identifier
        self.artifacts = artifacts
        self.sequence = 0

    def call(self, *arguments: str) -> dict:
        self.sequence += 1
        stem = f"{self.sequence:03d}-{arguments[1]}"
        output = self.artifacts / f"{stem}.json"
        log = self.artifacts / f"{stem}.log"
        # Unique JSON paths prevent a failed call from reusing an earlier receipt.
        # launch treats everything after the bundle ID as application arguments.
        # Device/receipt options must precede the first positional app argument.
        command = ["xcrun", "devicectl", "device", *arguments[:2],
                   "--device", self.identifier, "--timeout", "30",
                   "--json-output", str(output), *arguments[2:]]
        try:
            with log.open("w") as stream:
                completed = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, timeout=40)
        except subprocess.TimeoutExpired as error:
            raise SmokeFailure(f"Device command timed out; see {log}") from error
        if completed.returncode != 0:
            raise SmokeFailure(f"Device command failed (exit {completed.returncode}); see {log}")
        try:
            document = json.loads(output.read_text())
            if document["info"]["outcome"] != "success":
                raise ValueError("non-success outcome")
            result = document["result"]
            if not isinstance(result, dict):
                raise ValueError("non-object result")
            return result
        except (OSError, KeyError, TypeError, ValueError) as error:
            raise SmokeFailure(f"Missing/invalid successful device receipt: {output}") from error


def launch_identity(result: dict, executable_name: str) -> tuple[int, str]:
    try:
        process = result["process"]
        pid = process["processIdentifier"]
        executable = process["executable"]
        if type(pid) is not int or pid <= 0:
            raise ValueError("invalid PID")
        url = urlparse(executable)
        if url.scheme != "file" or Path(unquote(url.path)).name != executable_name:
            raise ValueError("wrong executable")
        return pid, executable
    except (KeyError, TypeError, ValueError) as error:
        raise SmokeFailure("Launch response has no valid app PID/executable") from error


def verify_process(result: dict, identity: tuple[int, str]) -> None:
    processes = result.get("runningProcesses")
    if not isinstance(processes, list):
        raise SmokeFailure("Missing process list; cannot attest launch survival")
    pid, executable = identity
    if not any(isinstance(p, dict) and p.get("processIdentifier") == pid
               and p.get("executable") == executable for p in processes):
        raise SmokeFailure(f"Launched app PID {pid} disappeared or was replaced (crash/termination)")


def cold_launches(device: Device, bundle: str, executable: str, launches: int,
                  seconds: float, *, clock=time.monotonic, sleep=time.sleep) -> list[dict]:
    receipts = []
    previous_pid = None
    for iteration in range(1, launches + 1):
        identity = launch_identity(
            device.call("process", "launch", "--terminate-existing", bundle), executable)
        if identity[0] == previous_pid:
            raise SmokeFailure("PID was reused; cannot attest a fresh cold launch")
        previous_pid = identity[0]
        started = clock()
        samples = 0
        while True:
            verify_process(device.call("info", "processes"), identity)
            samples += 1
            elapsed = clock() - started
            if elapsed >= seconds:
                break
            sleep(min(1.0, seconds - elapsed))
        receipts.append({"launch": iteration, "pid": identity[0], "samples": samples,
                         "survived_seconds": elapsed})
        print(f"Launch {iteration}/{launches}: PID {identity[0]} survived {elapsed:.1f}s ({samples} checks)")
    return receipts


def positive_seconds(value: str) -> float:
    parsed = float(value)
    if not math.isfinite(parsed) or parsed < 5:
        raise argparse.ArgumentTypeError("watch window must be finite and at least 5 seconds")
    return parsed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="CoreDevice UUID or hardware UDID; never auto-selects a phone")
    parser.add_argument("--derived-data", type=Path, default=Path(tempfile.gettempdir()) / "vox-capture-device-dd")
    parser.add_argument("--configuration", choices=["Debug", "Release"], default="Debug")
    parser.add_argument("--launches", type=int, default=3)
    parser.add_argument("--seconds", type=positive_seconds, default=20.0)
    parser.add_argument("--allow-provisioning-updates", action="store_true", help="Opt in to Xcode profile updates")
    args = parser.parse_args()
    if args.launches < 2:
        parser.error("at least two cold launches are required")
    artifacts = Path(tempfile.mkdtemp(prefix="vox-capture-launch-"))
    print(f"Logs/JSON receipts: {artifacts}", flush=True)
    print("Installing this checkout over Vox.md, then cold-launching it. Keep the chosen phone unlocked.", flush=True)
    summary = {"device": args.device, "configuration": args.configuration, "passed": False}
    try:
        summary["head"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        summary["dirty"] = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True))
        command = ["xcodebuild", "build", "-project", str(ROOT / "Voxboard.xcodeproj"),
                   "-scheme", "Voxboard", "-configuration", args.configuration,
                   "-destination", f"platform=iOS,id={args.device}",
                   "-derivedDataPath", str(args.derived_data.resolve())]
        if args.allow_provisioning_updates:
            command.append("-allowProvisioningUpdates")
        with (artifacts / "build.log").open("w") as stream:
            subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT,
                           timeout=1200, check=True)
        app = args.derived_data.resolve() / "Build" / "Products" / f"{args.configuration}-iphoneos" / "Voxboard.app"
        with (app / "Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        bundle, executable = info["CFBundleIdentifier"], info["CFBundleExecutable"]
        device = Device(args.device, artifacts)
        device.call("install", "app", str(app))
        summary["bundle"] = bundle
        summary["launches"] = cold_launches(device, bundle, executable, args.launches, args.seconds)
        summary["passed"] = True
        print("PASS: repeated physical-device launch survival (not a UI responsiveness assertion)")
        return 0
    except (SmokeFailure, subprocess.SubprocessError, OSError, KeyError, ValueError) as error:
        summary["error"] = str(error)
        print(f"FAIL: {error}\nDiagnostics retained in {artifacts}", file=sys.stderr)
        return 1
    finally:
        (artifacts / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    sys.exit(main())
