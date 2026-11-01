#!/usr/bin/env python3
"""Validate shared intelligence inputs and retained, model-backed parity measurements."""
from __future__ import annotations
import argparse
import hashlib
import itertools
import json
import math
import re
import subprocess
from pathlib import Path
import wave

ROOT = Path(__file__).resolve().parents[3]
CORPUS = ROOT / "evaluations/local-intelligence/v1/corpus.json"
REPORTS = ROOT / "artifacts/validation/local-intelligence-2026-11-01"
CASE_IDS = ["sorted-people", "formal-request", "spanish-extraction", "factual-summary", "link-preservation", "speaker-ownership"]
MODEL_SHA256 = "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e"

# Receipts bind the implementation, not just a mutable branch name or a model filename.
EVALUATION_INPUTS = (
    "apps/android/platform-services/src/main/kotlin/md/vox/android/platformservices/LocalIntelligence.kt",
    "apps/android/platform-services/src/main/kotlin/md/vox/android/platformservices/InstructionModelManager.kt",
    "apps/android/platform-services/src/main/kotlin/md/vox/android/platformservices/IntelligenceEvaluation.kt",
    "apps/android/platform-services/src/main/kotlin/md/vox/android/platformservices/LocalSpeech.kt",
    "apps/android/platform-services/src/main/kotlin/md/vox/android/platformservices/SpeakerDiarization.kt",
    "apps/android/capture-domain/src/main/kotlin/md/vox/android/capturedomain/OnDeviceCaptureTextProcessor.kt",
    "apps/android/capture-domain/src/main/kotlin/md/vox/android/capturedomain/CaptureRepository.kt",
    "Packages/vox-core-rust/crates/vox-core/src/lib.rs",
    "apps/android/app/src/main/kotlin/md/vox/android/VoxApplication.kt",
    "apps/android/data/src/main/kotlin/md/vox/android/data/AndroidCaptureRepository.kt",
    "apps/android/app/src/main/cpp/intelligence.cpp", "apps/android/app/src/main/cpp/CMakeLists.txt",
    "apps/android/scripts/validate-intelligence-evaluations.py",
    "apps/android/scripts/device_model_network.py",
    "apps/android/scripts/build-intelligence-native.py", "apps/android/scripts/validate-local-intelligence.py",
    "apps/android/scripts/validate-local-speech.py", "apps/android/scripts/validate-named-speech-model.py",
    "apps/android/app/src/androidTest/kotlin/md/vox/android/OnDeviceIntelligenceEvaluationInstrumentationTest.kt",
    "apps/android/app/src/androidTest/kotlin/md/vox/android/LocalSpeechInferenceInstrumentationTest.kt",
    "apps/android/app/src/androidTest/kotlin/md/vox/android/NamedModelInferenceInstrumentationTest.kt",
    "Packages/VoxboardShared/Sources/VoxboardShared/IntelligenceEvaluation.swift",
    "Packages/VoxboardShared/Sources/VoxboardShared/SpeakerDiarizationService.swift",
    "Packages/VoxboardShared/Sources/VoxboardIntelligenceEvaluation/main.swift",
    "Packages/VoxboardShared/Sources/VoxboardIntelligenceEvaluation/SpeakerBenchmark.swift",
    "evaluations/local-intelligence/v1/corpus.json",
)

def implementation_hashes(root=ROOT):
    return {path: hashlib.sha256((root/path).read_bytes()).hexdigest() for path in EVALUATION_INPUTS}


def require(condition, message):
    if not condition: raise ValueError(message)

def validate_corpus(corpus, root=CORPUS.parent):
    require(corpus["schemaVersion"] == 1 and corpus["corpusID"] == "vox-local-intelligence-v1", "corpus identity drift")
    require([row["id"] for row in corpus["instructionCases"]] == CASE_IDS, "required instruction case inventory differs")
    require(len(corpus["speakerAudio"]) == 4 and len(set(row["speaker"] for row in corpus["speakerAudio"])) == 2, "speaker corpus must retain two real readers/four utterances")
    require(corpus["speakerMaximumAttributionError"] == 0, "Android zero-error target must not be weakened")
    for row in corpus["speakerAudio"]:
        file = root / row["file"]
        require(file.resolve().is_relative_to(root.resolve()), "unsafe audio path")
        require(hashlib.sha256(file.read_bytes()).hexdigest() == row["sha256"], "speaker audio digest changed")
        with wave.open(str(file)) as audio:
            require((audio.getnchannels(), audio.getsampwidth(), audio.getframerate()) == (1, 2, 16000), "speaker audio format differs")
            require(abs(audio.getnframes() / audio.getframerate() - row["durationSeconds"]) < 0.000001, "speaker duration changed")

def speaker_error(reference, predicted, weights):
    require(len(reference) == len(predicted) == len(weights) > 0, "speaker report lost turns")
    require(all(isinstance(w, (int,float)) and math.isfinite(w) and w > 0 for w in weights), "invalid speaker weights")
    truth, labels = sorted(set(reference)), sorted(set(predicted))
    require(len(labels) <= 8 and len(truth) <= 8 and all(labels), "invalid speaker labels")
    # Pad reference identities with unmatched labels: predictions cannot merge to cheat.
    targets = truth + [f"__unmatched_{i}" for i in range(max(0,len(labels)-len(truth)))]
    best = 0
    for permutation in itertools.permutations(targets, len(labels)):
        mapping = dict(zip(labels, permutation))
        best = max(best, sum(w for actual,guess,w in zip(reference,predicted,weights) if mapping[guess] == actual))
    return 1 - best / sum(weights)

def validate_reports(corpus, reports):
    def load(name): return json.loads((reports / name).read_text())
    for platform, name in [("android", "instruction-evaluation.json"), ("apple", "apple-instruction-evaluation.json")]:
        data = load(name)
        require(data["corpusID"] == corpus["corpusID"] and data["platform"] == platform, "instruction report identity differs")
        require([row["id"] for row in data["results"]] == CASE_IDS, "instruction report missing/reordered cases")
        require(all(row["passed"] is True and row["response"].strip() and row["elapsedSeconds"] > 0 for row in data["results"]), "instruction quality gate failed")
        if platform == "android":
            require(data["modelSHA256"] == MODEL_SHA256, "unqualified instruction model")
            require(data.get("repositoryDeliveryVerified") is True and data.get("retryWithoutModelVerified") is True, "production delivery/retry did not execute")
    android = load("speaker-evaluation.json")
    apple = load("apple-speaker-evaluation.json")
    for data in (android, apple):
        require(data["corpusID"] == corpus["corpusID"], "speaker report identity differs")
        measured = speaker_error(data["reference"], data["predicted"], data["durations"])
        require(abs(measured - data["attributionError"]) < 0.000001, "speaker metric misreported")
    require(android["attributionError"] <= corpus["speakerMaximumAttributionError"], "Android speaker quality target failed")
    require(android["speakerCount"] == 2 and android["attributionError"] <= apple["attributionError"], "Android speaker parity regressed")
    require(apple["meetsZeroErrorTarget"] == (apple["attributionError"] < 0.000001), "Apple baseline target overclaimed")
    receipt = load("receipt.json")
    require(receipt["status"] == "passed" and receipt["fullPhoneSuite"] is True, "development-only run cannot qualify full model suite")
    require(receipt["counts"].get("validate-local-speech.py") == 2 and receipt["counts"].get("validate-named-speech-model.py") == 2, "four formerly skipped ASR tests did not execute")
    require(receipt["counts"].get("generalPhone",0) >= 84, "general phone suite incomplete")
    require(receipt["counts"].get("pinnedModelRunsSharedInstructionsOffline") == 1 and receipt["counts"].get("realSpeechSpeakerAttributionBenchmark") == 1, "live intelligence tests incomplete")
    require(receipt.get("implementationHashes") == implementation_hashes(), "evaluation implementation changed; rerun the full model gate")
    require(receipt.get("sourceTreeClean") is True, "model suite must run from a clean implementation commit")
    require(re.fullmatch(r"[0-9a-f]{40}", receipt["sourceRevision"]) is not None, "model suite source identity missing")
    require(subprocess.run(["git", "cat-file", "-e", receipt["sourceRevision"] + "^{commit}"], cwd=ROOT, capture_output=True).returncode == 0,
            "model suite source revision is not a real commit")
    require(subprocess.run(["git", "merge-base", "--is-ancestor", receipt["sourceRevision"], "HEAD"], cwd=ROOT, capture_output=True).returncode == 0,
            "model suite source revision is not an ancestor of HEAD")
    return {"androidInstructionCases": 6, "appleInstructionCases": 6,
            "androidSpeakerError": android["attributionError"], "appleSpeakerError": apple["attributionError"],
            "fourMandatoryModelTests": 4, "phoneTests": sum(receipt["counts"].values())}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--reports", type=Path, default=REPORTS)
    parser.add_argument("--corpus-only", action="store_true")
    args = parser.parse_args()
    corpus = json.loads(CORPUS.read_text())
    try:
        validate_corpus(corpus)
        results = {} if args.corpus_only else validate_reports(corpus,args.reports)
    except (ValueError, KeyError, OSError) as error: raise SystemExit(f"Local intelligence evaluation validation failed: {error}")
    print("Local intelligence evaluation validation passed: " + json.dumps(results, sort_keys=True))

if __name__ == "__main__": main()
