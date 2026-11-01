#!/usr/bin/env python3
"""Run the phone suite and mandatory, exact-hash offline model qualification phases."""
from __future__ import annotations
import argparse
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = {
    "instruction-model.gguf": ("https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/91cad51170dc346986eccefdc2dd33a9da36ead9/qwen2.5-1.5b-instruct-q4_k_m.gguf", 1117320736, "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e"),
    "vosk-model-small-en-us-0.15.zip": ("https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip", 41205931, "30f26242c4eb449f948e42cb302dd7a686cb29a3423a8367f99ff41780942498"),
    "vosk-api-test.wav": ("https://raw.githubusercontent.com/alphacep/vosk-api/78e66149f8ac56a64aa64306c1e8fc132c4eb154/python/example/test.wav", 265914, "dcfea5712c43a43ba7ae8083afb39d36993e5a69c46e88b68aaa72b65cb615bb"),
    "vosk-model-spk-0.4.zip": ("https://alphacephei.com/vosk/models/vosk-model-spk-0.4.zip", 13869103, "a74d8f51144484813e16af689bb0f916b7a111e2347f467c4933c1166097b5a7"),
}

def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""): value.update(chunk)
    return value.hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixtures", type=Path, default=ROOT / "app/build/qualification-fixtures")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--download-fixtures", action="store_true")
    parser.add_argument("--only-speakers", action="store_true", help="Development-only: run the acoustic benchmark only")
    parser.add_argument("--only-intelligence", action="store_true", help="Development-only: skip general/four ASR tests; receipt records this explicitly")
    args = parser.parse_args()
    serial = os.environ.get("ANDROID_SERIAL")
    if not serial or not os.environ.get("ANDROID_HOME"): raise SystemExit("ANDROID_SERIAL and ANDROID_HOME are required")
    adb = str(Path(os.environ["ANDROID_HOME"]) / "platform-tools/adb")
    def device(*command):
        result = subprocess.run([adb, "-s", serial, *command], text=True, capture_output=True, check=True)
        return result.stdout
    if device("shell", "getprop", "ro.kernel.qemu").strip() != "1": raise SystemExit("This destructive fixture gate requires an explicitly selected emulator")
    args.fixtures.mkdir(parents=True, exist_ok=True)
    for name, (url, size, expected) in FIXTURES.items():
        path = args.fixtures / name
        if not path.exists() and args.download_fixtures:
            partial = path.with_suffix(".downloading")
            urllib.request.urlretrieve(url, partial)
            partial.replace(path)
        if not path.is_file() or path.stat().st_size != size or digest(path) != expected:
            raise SystemExit(f"missing or changed pinned fixture: {path}")
    args.output.mkdir(parents=True, exist_ok=True)
    package = "md.vox.android"
    runner = package + ".test/androidx.test.runner.AndroidJUnitRunner"
    def instrument(name, *arguments):
        output = device("shell", "am", "instrument", "-w", "-r", *arguments, runner)
        (args.output / (name + ".log")).write_text(output)
        codes = re.findall(r"^INSTRUMENTATION_STATUS_CODE: (-?\d+)", output, re.M)
        if "INSTRUMENTATION_CODE: -1" not in output or not codes or any(code not in {"0", "1"} for code in codes):
            raise SystemExit(f"model tests failed, crashed or skipped: {name}; see retained log")
        return codes.count("0")
    artifact_hashes = {"app": digest(ROOT / "app/build/outputs/apk/debug/app-debug.apk"),
        "tests": digest(ROOT / "app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk")}
    device_metadata = {"serial": serial, "avd": device("shell", "getprop", "ro.boot.qemu.avd_name").strip(),
        "apiLevel": device("shell", "getprop", "ro.build.version.sdk").strip(),
        "abi": device("shell", "getprop", "ro.product.cpu.abi").strip()}
    device("install", "-r", "-g", str(ROOT / "app/build/outputs/apk/debug/app-debug.apk"))
    device("install", "-r", "-g", str(ROOT / "app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk"))
    counts = {}
    if not (args.only_intelligence or args.only_speakers):
        device("shell", "pm", "clear", package)
        counts["generalPhone"] = instrument("general-phone", "-e", "notAnnotation", "md.vox.android.ProvisionedModelTest")
        environment = dict(os.environ, VOX_TEST_VOSK_MODEL_ZIP=str(args.fixtures / "vosk-model-small-en-us-0.15.zip"),
            VOX_TEST_SPEECH_WAV=str(args.fixtures / "vosk-api-test.wav"), VOX_TEST_NAMED_MODEL_ID="ggml-tiny")
        for script, count in (("validate-local-speech.py", 2), ("validate-named-speech-model.py", 2)):
            result = subprocess.run([sys.executable, str(ROOT / "scripts" / script)], env=environment, text=True, capture_output=True)
            (args.output / (script + ".log")).write_text(result.stdout + result.stderr)
            if result.returncode: raise SystemExit(f"mandatory model phase failed: {script}")
            counts[script] = count
    previous = device("shell", "settings", "get", "global", "airplane_mode_on").strip()
    try:
        device("shell", "pm", "clear", package)
        for name in FIXTURES:
            device("push", str(args.fixtures / name), "/data/local/tmp/vox-intelligence-" + name)
            device("shell", "chmod", "0644", "/data/local/tmp/vox-intelligence-" + name)
            device("shell", "run-as", package, "mkdir", "-p", "files/local-intelligence-qualification")
            device("shell", "run-as", package, "cp", "/data/local/tmp/vox-intelligence-" + name, "files/local-intelligence-qualification/" + name)
            device("shell", "rm", "-f", "/data/local/tmp/vox-intelligence-" + name)
        device("shell", "cmd", "connectivity", "airplane-mode", "enable")
        phases = [("realSpeechSpeakerAttributionBenchmark", "speaker-evaluation.json")]
        if not args.only_speakers: phases.insert(0, ("pinnedModelRunsSharedInstructionsOffline", "instruction-evaluation.json"))
        for method, report in phases:
            # Retain reports even when a quality assertion fails.
            try:
                counts[method] = instrument(method, "-e", "class", "md.vox.android.OnDeviceIntelligenceEvaluationInstrumentationTest#" + method)
            finally:
                retained = subprocess.run([adb, "-s", serial, "exec-out", "run-as", package, "cat", "files/" + report], text=True, capture_output=True)
                if retained.returncode == 0: (args.output / report).write_text(retained.stdout)
    finally:
        device("shell", "cmd", "connectivity", "airplane-mode", "enable" if previous == "1" else "disable")
        device("shell", "pm", "clear", package)
    spec = importlib.util.spec_from_file_location("intelligence_evaluation", ROOT / "scripts/validate-intelligence-evaluations.py")
    evaluator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(evaluator)
    receipt = {"artifactsSHA256": artifact_hashes, "device": device_metadata, "implementationHashes": evaluator.implementation_hashes(), "schemaVersion": 1, "status": "passed", "fullPhoneSuite": not (args.only_intelligence or args.only_speakers), "counts": counts,
        "fixtures": {name: details[2] for name, details in FIXTURES.items()},
        "sourceRevision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "sourceTreeClean": not subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()}
    (args.output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt, indent=2))

if __name__ == "__main__": main()
