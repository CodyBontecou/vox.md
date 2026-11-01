#!/usr/bin/env python3
"""The same source inventory is embedded into the test APK and checked by the host."""
import hashlib
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[3]
RECORDING_INPUTS=[
    "apps/android/platform-services/src/main/kotlin/md/vox/android/platformservices/AudioCapture.kt",
    "apps/android/platform-services/src/main/kotlin/md/vox/android/platformservices/RecordingFileRecovery.kt",
]
MODEL_INPUTS=[
    "apps/android/platform-services/src/main/kotlin/md/vox/android/platformservices/LocalIntelligence.kt",
    "apps/android/platform-services/src/main/kotlin/md/vox/android/platformservices/InstructionModelManager.kt",
    "apps/android/platform-services/src/main/kotlin/md/vox/android/platformservices/LocalSpeech.kt",
    "apps/android/capture-domain/src/main/kotlin/md/vox/android/capturedomain/OnDeviceCaptureTextProcessor.kt",
    "apps/android/app/src/main/cpp/intelligence.cpp",
    "apps/android/app/src/main/cpp/CMakeLists.txt",
    "apps/android/scripts/build-intelligence-native.py",
    "apps/android/app/src/debug/kotlin/md/vox/android/PhysicalQualificationActivity.kt",
]

def source_hashes(paths):return {name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in paths}

def main():
    output=Path(sys.argv[1]);output.mkdir(parents=True,exist_ok=True)
    for name,inputs in [("physical-build.json",RECORDING_INPUTS),("physical-model-build.json",MODEL_INPUTS)]:
        (output/name).write_text(json.dumps(source_hashes(inputs),sort_keys=True)+"\n")

if __name__=="__main__":main()
