#!/usr/bin/env python3
"""Build the phone-only, pinned MIT llama.cpp runtime for all supported ABIs."""
import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import shutil
import tarfile
import urllib.request

REVISION = "74d4f5b041ad837153b0e90fc864b8290e01d8d5"
SOURCE_SHA256 = "8dd9fcc7c17f972673960ffdcc7521f52de5a9ec594aa6acebd9dfd8c17c0a5c"
ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    sdk = Path(os.environ.get("ANDROID_HOME", str(Path.home() / "Library/Android/sdk")))
    build = ROOT / "app/build/intelligence-native"
    build.mkdir(parents=True, exist_ok=True)
    archive = Path(os.environ.get("VOX_LLAMA_SOURCE_ARCHIVE", str(build / "llama.tar.gz")))
    if not archive.exists():
        temporary = archive.with_suffix(".downloading")
        urllib.request.urlretrieve(f"https://codeload.github.com/ggml-org/llama.cpp/tar.gz/{REVISION}", temporary)
        temporary.replace(archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise SystemExit("llama.cpp source digest mismatch")
    source = build / f"llama.cpp-{REVISION}"
    if source.exists():
        shutil.rmtree(source)
    # A populated build cache is never a substitute for the verified source archive.
    if not source.exists():
        with tarfile.open(archive) as package:
            for member in package.getmembers():
                name = Path(member.name)
                if name.is_absolute() or ".." in name.parts or member.issym() or member.islnk():
                    raise SystemExit("unexpected link/path in verified source archive")
            package.extractall(build)
    cmake = sdk / "cmake/3.22.1/bin/cmake"
    for abi in ("arm64-v8a", "armeabi-v7a", "x86", "x86_64"):
        target = build / abi
        subprocess.run([str(cmake), "-S", str(ROOT / "app/src/main/cpp"), "-B", str(target), "-G", "Ninja",
            f"-DCMAKE_MAKE_PROGRAM={sdk}/cmake/3.22.1/bin/ninja",
            f"-DCMAKE_TOOLCHAIN_FILE={sdk}/ndk/27.1.12297006/build/cmake/android.toolchain.cmake",
            f"-DANDROID_ABI={abi}", "-DANDROID_PLATFORM=android-28", "-DANDROID_STL=c++_static",
            "-DCMAKE_BUILD_TYPE=Release", f"-DLLAMA_SOURCE={source}",
            f"-DCMAKE_LIBRARY_OUTPUT_DIRECTORY={args.output.resolve() / abi}"], check=True)
        subprocess.run([str(cmake), "--build", str(target), "--target", "vox_intelligence", "-j", "4"], check=True)

if __name__ == "__main__": main()
