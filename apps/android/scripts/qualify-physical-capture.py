#!/usr/bin/env python3
"""Physical-only capture qualification. Never pull microphone payloads or clear owner data."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
import math
from physical_capture_provenance import RECORDING_INPUTS, MODEL_INPUTS, source_hashes

ROOT = Path(__file__).resolve().parents[3]
PACKAGE = "md.vox.android.qualification"
ACTIVITY = PACKAGE + "/md.vox.android.PhysicalQualificationActivity"
def hashes(): return source_hashes(RECORDING_INPUTS)
def model_hashes(): return source_hashes(MODEL_INPUTS)

def validate_endurance(report):
    if report.get("scenario") != "physical-60-minute-microphone":
        raise ValueError("synthetic/imported audio is not microphone endurance evidence")
    if report["device"]["emulator"] or report["device"]["manufacturer"].lower() not in {"google", "samsung"}:
        raise ValueError("physical Pixel/Samsung required")
    if not math.isfinite(report["wallSeconds"]) or report["wallSeconds"] < 3600 or report["final"]["finalizedBytes"] < 3600 * 32000:
        raise ValueError("a real 60-minute microphone recording is required")
    if report["final"]["phase"] != "COMPLETED" or not report["final"]["wavExportVerified"]:
        raise ValueError("completed, exportable recording required")
    if report["final"].get("wavHeaderVerified") is not True:
        raise ValueError("PCM WAV header verification required")
    if report["final"]["wavBytes"] != report["final"]["finalizedBytes"] + 44:
        raise ValueError("WAV payload size differs")
    chunks=report["final"]["chunks"]
    if len(chunks)!=report["final"]["finalizedChunks"] or sum(c["bytes"] for c in chunks)!=report["final"]["finalizedBytes"]:
        raise ValueError("final chunk inventory differs from audio size")
    if any(c["name"]!=f"chunk-{i:06d}.pcm" or not re.fullmatch(r"[0-9a-f]{64}",c["sha256"]) or
           not 0<c["bytes"]<=64000 or (i<len(chunks)-1 and c["bytes"]!=64000) for i,c in enumerate(chunks)):
        raise ValueError("uninterrupted PCM chunk sequence differs")
    if report["sampleCount"] < 200 or report["maximumSampleGapSeconds"] > 45:
        raise ValueError("telemetry coverage incomplete")
    if report["processChanged"] or report["recordingInterrupted"]:
        raise ValueError("endurance run must be uninterrupted")
    if report["startImplementationHashes"] != report["endImplementationHashes"]:
        raise ValueError("recording implementation changed during measurement")
    if report["installedBuildHashes"] != report["startImplementationHashes"]:
        raise ValueError("installed recorder differs from measured source")

class Device:
    def __init__(self, serial):
        sdk = os.environ.get("ANDROID_HOME", str(Path.home()/"Library/Android/sdk"))
        self.sdk = Path(sdk)
        self.prefix = [str(Path(sdk)/"platform-tools/adb"), "-s", serial]
    def run(self, *args, timeout=45):
        result = subprocess.run(self.prefix+list(args), text=True, capture_output=True, timeout=timeout, check=True)
        return result.stdout
    def shell(self, *args): return self.run("shell", *args)
    def command(self, command):
        result = self.shell("am", "start", "-W", "-f", "0x14000000", "-n", ACTIVITY, "--es", "command", command)
        if "Error:" in result or "Status: ok" not in result or "md.vox.android.PhysicalQualificationActivity" not in result:
            raise RuntimeError("Qualification command was not dispatched")
        return result
    def read(self, name): return json.loads(self.run("exec-out", "run-as", PACKAGE, "cat", f"files/physical-qualification/{name}.json"))
    def apk_hash(self):
        path=self.shell("pm","path",PACKAGE).strip().splitlines()[0].removeprefix("package:")
        value=self.shell("sha256sum",path).split()[0]
        if not re.fullmatch(r"[a-f0-9]{64}",value): raise ValueError("APK identity missing")
        return value
    def identity(self):
        return {"manufacturer": self.shell("getprop", "ro.product.manufacturer").strip(),
                "model": self.shell("getprop", "ro.product.model").strip(),
                "api": self.shell("getprop", "ro.build.version.sdk").strip(),
                "buildFingerprint": self.shell("getprop", "ro.build.fingerprint").strip(),
                "emulator": self.shell("getprop", "ro.kernel.qemu").strip() == "1"}

def validate_install_identity(badging):
    package=re.search(r"^package: name='([^']+)'",badging,re.M)
    if package is None or package[1]!=PACKAGE or "application-debuggable" not in badging:
        raise ValueError("Refusing to install an owner/release APK; build -PvoxPhysicalQualification=true")

def install(device,apk):
    if device.identity()["emulator"]:raise ValueError("Select the authorized physical device explicitly")
    badging=subprocess.run([str(device.sdk/"build-tools/36.0.0/aapt2"),"dump","badging",str(apk)],capture_output=True,text=True,check=True).stdout
    validate_install_identity(badging)
    print(device.run("install","-r","-t",str(apk),timeout=180).strip())

def start_device_record(device):
    if device.identity()["emulator"]:raise ValueError("Physical on-device endurance requires hardware")
    ensure_idle(device)
    device.shell("run-as",PACKAGE,"rm","-f","files/physical-qualification/device-endurance-latest.json")
    device.command("device-endurance")
    run=wait_report(device,"device-endurance-latest")
    print("On-device hour test started:",run["runID"],"; USB may disconnect. Collect its report after completion.")

def collect_device_record(device,output):
    identity=device.identity()
    if identity["emulator"]:raise ValueError("Physical collector refuses emulators")
    run= device.read("device-endurance-latest")["runID"]
    if not re.fullmatch(r"[0-9a-f-]{36}",run):raise ValueError("Invalid on-device run identity")
    base="files/physical-qualification/device-endurance/"+run+"/"
    report=json.loads(device.run("exec-out","run-as",PACKAGE,"cat",base+"endurance.json"))
    if report.get("measurementProducer")!="device-local-monotonic":raise ValueError("Wrong measurement producer")
    if report["device"]!=identity:raise ValueError("Report came from a different device/build")
    if report["producerBuildHashes"]!=model_hashes() or report["apkSHA256"]!=device.apk_hash():raise ValueError("Observer sources/APK changed")
    validate_endurance(report)
    output.mkdir(parents=True,exist_ok=False)
    telemetry=device.run("exec-out","run-as",PACKAGE,"cat",base+"samples.ndjson")
    (output/"samples.ndjson").write_text(telemetry)
    (output/"endurance.json").write_text(json.dumps(report,indent=2)+"\n")
    print("Collected complete on-device microphone endurance; raw audio remains private")

def models(device,output,fixtures):
    identity=device.identity()
    if identity["emulator"]: raise ValueError("Physical model measurements require hardware")
    ensure_idle(device)
    output.mkdir(parents=True,exist_ok=False)
    pins={"instruction-model.gguf":"6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e",
          "vosk-model-small-en-us-0.15.zip":"30f26242c4eb449f948e42cb302dd7a686cb29a3423a8367f99ff41780942498",
          "vosk-api-test.wav":"dcfea5712c43a43ba7ae8083afb39d36993e5a69c46e88b68aaa72b65cb615bb"}
    paths={name:fixtures/name for name in pins}
    for name,path in paths.items():
        digest=hashlib.sha256()
        with path.open("rb") as source:
            for chunk in iter(lambda:source.read(1024*1024),b""):digest.update(chunk)
        if digest.hexdigest()!=pins[name]: raise ValueError("Public model fixture changed: "+name)
    paths["corpus.json"]=ROOT/"evaluations/local-intelligence/v1/corpus.json"
    device.command("status")
    if device.read("model-build")!=model_hashes():raise ValueError("Installed inference/harness sources differ; rebuild qualification APK")
    apk=device.apk_hash()
    for name,path in paths.items():
        temporary="/data/local/tmp/vox-physical-"+name
        try:
            device.run("push",str(path),temporary,timeout=180)
            device.shell("chmod","0644",temporary)
            device.shell("run-as",PACKAGE,"cp",temporary,"files/physical-qualification/"+name)
        finally:device.shell("rm","-f",temporary)
    for kind in ["speech","instructions"]:
        device.shell("run-as",PACKAGE,"rm","-f","files/physical-qualification/"+kind+".json")
        device.command(kind)
        report=wait_report(device,kind,timeout=16*60)
        report.update(device=identity,apkSHA256=apk,implementationHashes=model_hashes(),installedBuildHashes=device.read("model-build"))
        (output/(kind+".json")).write_text(json.dumps(report,indent=2)+"\n")
        name="instruction-memory.ndjson" if kind=="instructions" else "speech-memory.ndjson"
        telemetry=device.run("exec-out","run-as",PACKAGE,"cat","files/physical-qualification/"+name)
        (output/name).write_text(telemetry)
        if report.get("status")=="failed":raise ValueError("Physical model campaign failed: "+kind)
    if device.apk_hash()!=apk:raise ValueError("APK changed during model measurements")
    print("Physical model measurements retained: three ASR and eighteen instruction requests")

def wait_report(device, name, predicate=lambda value: True, timeout=45):
    deadline = time.monotonic()+timeout
    while time.monotonic()<deadline:
        try:
            value = device.read(name)
            if predicate(value): return value
        except (subprocess.SubprocessError, json.JSONDecodeError): pass
        time.sleep(.5)
    raise RuntimeError("Missing qualification report: "+name)

def preserved_prefix(before, after):
    for value in (before, after):
        if len({row["name"] for row in value["chunks"]}) != len(value["chunks"]): return False
        if any(not re.fullmatch(r"chunk-[0-9]{6}\.pcm",row["name"]) or row["bytes"] < 0 or
               not re.fullmatch(r"[0-9a-f]{64}",row["sha256"]) for row in value["chunks"]): return False
    previous = {row["name"]:(row["bytes"],row["sha256"]) for row in before["chunks"]}
    retained = {row["name"]:(row["bytes"],row["sha256"]) for row in after["chunks"]}
    return bool(previous) and before["sessionID"] == after["sessionID"] and all(retained.get(k)==v for k,v in previous.items())

def checkpoint(device):
    device.shell("run-as", PACKAGE, "rm", "-f", "files/physical-qualification/checkpoint.json")
    device.command("checkpoint")
    return wait_report(device,"checkpoint")

def ensure_idle(device):
    if checkpoint(device)["phase"] in {"RECORDING","PAUSED"}:
        raise ValueError("Another recording is active; it was left untouched")

def credential_storage_unlocked(device):
    # API 37 does not expose `cmd user is-user-unlocked`. ActivityManager's
    # explicit state plus an app-private CE lookup proves reboot recovery can read it.
    if device.shell("am","get-started-user-state","0").strip()!="RUNNING_UNLOCKED":return False
    device.shell("run-as",PACKAGE,"test","-d","files")
    return True

def recovery(device, output, mode):
    identity = device.identity()
    if identity["emulator"]: raise ValueError("Physical recovery campaign refuses emulators")
    ensure_idle(device)
    output.mkdir(parents=True,exist_ok=False)
    try:
        device.command("start")
        wait_report(device,"status",lambda r:r["phase"]=="RECORDING")
        time.sleep(15)
        before = checkpoint(device)
        pid_before = device.shell("pidof",PACKAGE).strip()
        boot_before = device.shell("cat","/proc/sys/kernel/random/boot_id").strip()
        if mode == "sigkill": device.shell("run-as",PACKAGE,"kill","-9",pid_before)
        elif mode == "force-stop": device.shell("am","force-stop",PACKAGE)
        elif mode == "reboot": device.run("reboot")
        else: raise ValueError("Unknown failure mode")
        deadline = time.monotonic()+300
        while time.monotonic()<deadline:
            try:
                booted = device.shell("getprop","sys.boot_completed").strip()=="1"
                unlocked = credential_storage_unlocked(device)
                if booted and unlocked: break
            except subprocess.SubprocessError: pass
            time.sleep(5)
        else: raise RuntimeError("Physical device is unavailable or needs unlocking")
        boot_after = device.shell("cat","/proc/sys/kernel/random/boot_id").strip()
        recovered = checkpoint(device)
        if recovered["phase"] != "INTERRUPTED" or not preserved_prefix(before,recovered):
            raise ValueError("Interrupted recovery did not preserve every finalized chunk")
        if device.shell("pidof",PACKAGE).strip()==pid_before and mode != "reboot":
            raise ValueError("Process did not actually change")
        if (boot_before!=boot_after) != (mode=="reboot"): raise ValueError("Reboot identity does not match the requested fault")
        device.command("resume")
        wait_report(device,"status",lambda r:r["phase"]=="RECORDING" and r["sessionID"]==before["sessionID"])
        time.sleep(15)
        device.command("stop"); device.command("finalize")
        final = wait_report(device,"final",lambda r:r["sessionID"]==before["sessionID"])
        if not preserved_prefix(recovered,final) or not final["wavExportVerified"] or final["phase"]!="COMPLETED":
            raise ValueError("Resumed recording lost audio or exportability")
        report = {"schemaVersion":1,"scenario":"physical-recording-"+mode,"status":"passed","device":identity,
            "before":before,"recovered":recovered,"final":final,"implementationHashes":hashes(),
            "installedBuildHashes":device.read("build"),"processChanged":True,"rebootVerified":mode=="reboot"}
        (output/"recovery.json").write_text(json.dumps(report,indent=2)+"\n")
    except Exception as error:
        (output/"failure.json").write_text(json.dumps({"status":"incomplete","reason":type(error).__name__},indent=2)+"\n")
        raise
    finally:
        try: device.command("stop")
        except Exception: (output/"cleanup-required.json").write_text('{"stopConfirmed":false}\n')

def record(device, output):
    identity = device.identity()
    if identity["emulator"] or identity["manufacturer"].lower() not in {"google", "samsung"}:
        raise SystemExit("This campaign requires a physical Pixel or Samsung")
    ensure_idle(device)
    output.mkdir(parents=True, exist_ok=False)
    try:
        return record_started(device, output)
    except Exception as error:
        (output/"failure.json").write_text(json.dumps({"status":"incomplete", "reason":type(error).__name__,
            "enduranceQualified":False}, indent=2)+"\n")
        raise
    finally:
        try: device.command("stop")
        except Exception:
            (output/"cleanup-required.json").write_text(json.dumps({"stopConfirmed":False,
                "instruction":"Reconnect this device and stop the qualification recording; its notification also has Stop."}, indent=2)+"\n")

def record_started(device, output):
    identity = device.identity()
    if identity["emulator"]: raise SystemExit("Physical recording campaign refuses emulators")
    source = hashes()
    device.command("start")
    if device.read("build") != source: raise RuntimeError("Installed recorder sources differ; rebuild qualification APK")
    deadline = time.monotonic() + 45
    while True:
        try:
            first = device.read("status")
            if first["phase"] == "RECORDING": break
        except (subprocess.SubprocessError, json.JSONDecodeError): pass
        if time.monotonic() > deadline: raise RuntimeError("microphone did not start")
        time.sleep(1)
    pid = device.shell("pidof", PACKAGE).strip()
    started = last = time.monotonic()
    gaps, samples = [], []
    interrupted = changed = False
    try:
        with (output/"samples.ndjson").open("w") as stream:
            while True:
                now = time.monotonic()
                if now-started > 65*60+30: raise RuntimeError("bounded recording campaign timed out")
                sample = device.read("status")
                sample["hostElapsedSeconds"] = now - started
                sample["battery"] = battery(device.shell("dumpsys", "battery"))
                sample["sameProcess"] = device.shell("pidof", PACKAGE).strip() == pid
                gaps.append(now-last); last=now
                changed |= not sample["sameProcess"]
                interrupted |= sample["phase"] != "RECORDING" or sample["sessionID"] != first["sessionID"]
                samples.append(sample)
                if len(samples) >= 4 and sample["uptimeMillis"] <= samples[-4]["uptimeMillis"]:
                    raise RuntimeError("device telemetry stopped advancing")
                stream.write(json.dumps(sample, sort_keys=True)+"\n"); stream.flush(); os.fsync(stream.fileno())
                if interrupted or changed: raise RuntimeError("recording process/state changed during endurance")
                if now-started >= 3600 and sample["finalizedBytes"] >= 3600*32000: break
                time.sleep(15)
    finally:
        device.command("stop")
    device.command("finalize")
    for attempt in range(30):
        try:
            final = device.read("final")
            if final["sessionID"] == first["sessionID"]: break
        except (subprocess.SubprocessError, json.JSONDecodeError): pass
        time.sleep(1)
    else: raise RuntimeError("final audio verification missing")
    report = {"schemaVersion": 1, "scenario": "physical-60-minute-microphone", "device": identity,
        "wallSeconds": time.monotonic()-started, "sampleCount": len(samples), "maximumSampleGapSeconds": max(gaps),
        "processChanged": changed, "recordingInterrupted": interrupted,
        "startImplementationHashes": source, "endImplementationHashes": hashes(), "final": final,
        "installedBuildHashes": device.read("build"),
        "peakPssKiB": max(s["pssKiB"] for s in samples), "maximumThermalStatus": max(s["thermalStatus"] for s in samples),
        "chargingObserved": any(s["battery"].get("acPowered") or s["battery"].get("usbPowered") for s in samples)}
    validate_endurance(report)
    report["status"] = "passed"
    (output/"endurance.json").write_text(json.dumps(report, indent=2)+"\n")
    print("Physical endurance passed: real 60-minute microphone capture; private WAV verified on device")

def battery(text):
    result = {}
    for source, target in [("level", "level"), ("temperature", "temperatureTenthsC")]:
        match = re.search(r"^\s*"+source+r": (\d+)$", text, re.M)
        if match: result[target] = int(match[1])
    for source, target in [("AC powered", "acPowered"), ("USB powered", "usbPowered")]:
        match = re.search(r"^\s*"+source+r": (true|false)$", text, re.M)
        if match: result[target] = match[1] == "true"
    return result

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["install", "record", "record-device", "collect-device", "models", "identity", "sigkill", "force-stop", "reboot", "start", "stop", "pause", "resume", "status", "checkpoint", "finalize", "instructions", "speech", "choose-provider", "provider-capture", "provider-retry", "provider-revoke"])
    parser.add_argument("--serial", required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--fixtures",type=Path,default=ROOT/"apps/android/app/build/qualification-fixtures")
    parser.add_argument("--apk",type=Path,default=ROOT/"apps/android/app/build/outputs/apk/debug/app-debug.apk")
    args = parser.parse_args()
    device = Device(args.serial)
    if args.action == "identity": print(json.dumps(device.identity(), indent=2))
    elif args.action == "install":install(device,args.apk)
    elif args.action == "record-device":start_device_record(device)
    elif args.action == "collect-device":
        if args.output is None:parser.error("collect-device requires --output")
        collect_device_record(device,args.output)
    elif args.action == "models":
        if args.output is None:parser.error("models requires --output")
        models(device,args.output,args.fixtures)
    elif args.action == "record":
        if args.output is None: parser.error("record requires --output")
        record(device, args.output)
    elif args.action in {"sigkill","force-stop","reboot"}:
        if args.output is None: parser.error("recovery requires --output")
        recovery(device,args.output,args.action)
    else: print(device.command(args.action))

if __name__ == "__main__": main()
