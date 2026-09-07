#!/usr/bin/env python3
"""Run synthetic text evaluations against the production backend using a Mac Debug build.

Example: DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
python3 scripts/run-foundation-model-evaluations.py /tmp/vox-intelligence-mac

Build the Voxboard Mac scheme at that DerivedData path first. Exit 2 means model
assets/Apple Intelligence are unavailable. This script never enables system features.
"""
from pathlib import Path
import argparse
import os
import platform
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("derived_data", type=Path, help="DerivedData from a Debug build of Voxboard Mac")
derived_data = parser.parse_args().derived_data.resolve()
products = derived_data / "Build/Products/Debug"
wrappers = derived_data / "SourcePackages/checkouts/FluidAudio/Sources"
objects = [products / f"{name}.o" for name in
           ("VoxboardShared", "VoxboardCaptureCore", "FluidAudio", "FastClusterWrapper", "MachTaskSelfWrapper", "ExportKit")]
with tempfile.TemporaryDirectory(prefix="vox-model-eval-") as directory:
    executable = Path(directory) / "evaluate"
    command = ["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library", "-swift-version", "5",
               "-target", f"{platform.machine()}-apple-macos26.0", "-I", str(products), "-F", str(products),
               "-F", str(products / "PackageFrameworks"),
               "-I", str(wrappers / "FastClusterWrapper/include"),
               "-I", str(wrappers / "MachTaskSelfWrapper/include"),
               str(root / "Voxboard/FoundationModelsBackend.swift"),
               str(root / "scripts/evaluate-foundation-models.swift"),
               *map(str, objects), "-lc++", "-framework", "whisper", "-framework", "Accelerate",
               "-framework", "Metal", "-framework", "CoreML", "-framework", "Security", "-o", str(executable)]
    subprocess.run(command, check=True)
    env = dict(os.environ)
    env["DYLD_FRAMEWORK_PATH"] = str(products)
    completed = subprocess.run([str(executable)], env=env)
    sys.exit(completed.returncode)
