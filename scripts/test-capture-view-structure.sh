#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/vox-capture-structure.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# Use the selected Xcode's parser; no network download or SwiftSyntax package pin.
SWIFTC="$(xcrun --find swiftc)"
HOST="$(dirname "$SWIFTC")/../lib/swift/host"
xcrun swiftc -I "$HOST" -L "$HOST" -Xlinker -rpath -Xlinker "$HOST" \
    "$ROOT/scripts/validate-capture-view-structure.swift" -o "$WORK/validate"
"$WORK/validate" --self-test
"$WORK/validate" \
    "$ROOT/Voxboard/Views/QuickCaptureView.swift" \
    "$ROOT/Voxboard/Capture/CaptureViewSection.swift" \
    "$ROOT/Voxboard/Capture/QuickCaptureCanvas.swift"
