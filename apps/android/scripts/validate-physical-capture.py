#!/usr/bin/env python3
"""Validate truthful physical qualification evidence; completeness is a separate gate."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[3]
REPORTS=ROOT/"artifacts/validation/android-physical-capture-2026-11-01"
sys.path.insert(0,str(Path(__file__).parent))
SPEC=importlib.util.spec_from_file_location("physical_runner",Path(__file__).with_name("qualify-physical-capture.py"))
RUNNER=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(RUNNER)
REQUIRED={f"{family}.{case}" for family in ["pixel","samsung"] for case in
          ["endurance","sigkill","force-stop","reboot","speech","instructions"]}|{"drive.delivery-retry","onedrive.delivery-retry"}

def require(condition,message):
    if not condition: raise ValueError(message)

def validate_model(report,samples,kind):
    require(report.get("status")!="failed","model campaign failed")
    rows=report["results"]
    expected=[(r,c) for r in range(3) for c in ["sorted-people","formal-request","spanish-extraction","factual-summary","link-preservation","speaker-ownership"]]
    if kind=="instructions":
        require([(r["round"],r["id"]) for r in rows]==expected,"instruction rounds incomplete")
        require(report["modelSHA256"]=="6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e","model identity differs")
    else:
        require([r["round"] for r in rows]==[0,1,2] and report["modelID"]=="vosk-small-en-us-0.15","speech rounds incomplete")
    require(all(r["passed"] is True and 0<r["elapsedMillis"]<=120_000 for r in rows),"model quality/deadline failed")
    require(len(samples)>=2,"model memory sampling incomplete")
    require(all(0<=s["thermalStatus"]<3 and not s["lowMemory"] for s in samples),"thermal/memory safety target failed or unavailable")
    require(max(s["pssKiB"] for s in samples)<=2*1024*1024,"sampled model PSS exceeds 2 GiB target")

def validate_export(final,proof):
    require(proof["wavHeaderVerified"] is True and proof["wavExportVerified"] is True,"PCM WAV header/export failed")
    require(proof["sessionID"]==final["sessionID"] and proof["wavSHA256"]==final["wavSHA256"] and proof["wavBytes"]==final["wavBytes"],"export verification describes different audio")

def validate_matrix(matrix,root=REPORTS,complete=False):
    require(matrix["schemaVersion"]==1,"physical evidence schema differs")
    require(set(matrix["cases"])==REQUIRED,"physical campaign inventory differs")
    for case,row in matrix["cases"].items():
        require(row["status"] in {"passed","incomplete","unavailable","planned"},"invalid physical campaign status")
        if row["status"]!="passed":
            require(bool(row.get("reason")),"unfinished campaign needs a reason")
            continue
        path=root/row["artifact"]
        require(path.resolve().is_relative_to(root.resolve()),"unsafe physical artifact path")
        require(hashlib.sha256(path.read_bytes()).hexdigest()==row["sha256"],"physical artifact hash differs")
        report=json.loads(path.read_text())
        require(not report["device"]["emulator"],"emulator cannot qualify physical parity")
        expected="google" if case.startswith("pixel.") else "samsung" if case.startswith("samsung.") else None
        if expected: require(report["device"]["manufacturer"].lower()==expected,"wrong physical device family")
        if case.endswith(".endurance"):
            RUNNER.validate_endurance(report)
            if report["final"].get("wavHeaderVerified") is True: validate_export(report["final"],report["final"])
            else:
                verification=json.loads((path.parent/"export-verification.json").read_text())
                require(verification["installedBuildHashes"]==RUNNER.hashes(),"export verifier source differs")
                validate_export(report["final"],verification["verification"])
            require(report["startImplementationHashes"]==RUNNER.hashes(),"recorder implementation changed")
            samples=[json.loads(line) for line in (path.parent/"samples.ndjson").read_text().splitlines()]
            require(len(samples)==report["sampleCount"],"endurance telemetry lost samples")
            require(all(s["phase"]=="RECORDING" and s["sameProcess"] for s in samples),"interrupted telemetry")
            require(all(b["uptimeMillis"]>=a["uptimeMillis"] and b["finalizedBytes"]>=a["finalizedBytes"] for a,b in zip(samples,samples[1:])),"regressing device telemetry")
            require(all(samples[i]["uptimeMillis"]>samples[i-3]["uptimeMillis"] for i in range(3,len(samples))),"stale device telemetry")
            require(report["peakPssKiB"]==max(s["pssKiB"] for s in samples) and report["peakPssKiB"]<=512*1024,"recording PSS target failed/misreported")
            require(report["maximumThermalStatus"]==max(s["thermalStatus"] for s in samples) and 0<=report["maximumThermalStatus"]<3,"recording thermal target failed/unavailable")
        elif case.endswith((".sigkill",".force-stop",".reboot")):
            require(report["status"]=="passed" and report["processChanged"],"process recovery did not execute")
            require(report["recovered"]["phase"]=="INTERRUPTED" and report["final"]["phase"]=="COMPLETED","recovery states differ")
            require(RUNNER.preserved_prefix(report["before"],report["recovered"]) and RUNNER.preserved_prefix(report["recovered"],report["final"]),"recovery changed retained PCM")
            require(report["rebootVerified"]==case.endswith(".reboot"),"reboot proof missing")
            validate_export(report["final"],report["final"])
            require(report["implementationHashes"]==report["installedBuildHashes"]==RUNNER.hashes(),"recovery source identity differs")
        elif case.endswith((".speech",".instructions")):
            kind=case.split('.')[1]
            samples=[json.loads(line) for line in (path.parent/("instruction-memory.ndjson" if kind=="instructions" else "speech-memory.ndjson")).read_text().splitlines()]
            validate_model(report,samples,kind)
            require(report["implementationHashes"]==report["installedBuildHashes"]==RUNNER.model_hashes(),"model/harness sources differ from the installed APK")
            require(len(report["apkSHA256"])==64,"model APK identity missing")
        else:
            require(report["providerPackage"]==("com.google.android.apps.docs" if case.startswith("drive.") else "com.microsoft.skydrive"),"surrogate provider cannot qualify cloud parity")
            require(report["baseline"]["result"]==report["retry"]["result"]=="Delivered","provider delivery/retry not verified")
            require(report["baseline"]["matchingDocumentCount"]==report["retry"]["matchingDocumentCount"]==1,"provider retry duplicated/lost the note")
            require(report["baseline"]["sha256"]==report["retry"]["sha256"] and len(report["retry"]["sha256"])==1,"provider bytes changed on retry")
    all_passed=all(r["status"]=="passed" for r in matrix["cases"].values())
    require(matrix["status"]==("passed" if all_passed else "incomplete"),"physical matrix overclaims completion")
    if complete: require(all_passed,"physical release qualification remains incomplete")
    return {"passed":sum(r["status"]=="passed" for r in matrix["cases"].values()),"total":len(REQUIRED),"status":matrix["status"]}

def main():
    p=argparse.ArgumentParser();p.add_argument("--reports",type=Path,default=REPORTS);p.add_argument("--require-complete",action="store_true");args=p.parse_args()
    try: result=validate_matrix(json.loads((args.reports/"matrix.json").read_text()),args.reports,args.require_complete)
    except (ValueError,KeyError,OSError) as error: raise SystemExit("Physical capture evidence validation failed: "+str(error))
    print("Physical capture evidence validated: "+json.dumps(result,sort_keys=True))

if __name__=="__main__":main()
