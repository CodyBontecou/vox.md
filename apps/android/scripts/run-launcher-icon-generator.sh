#!/usr/bin/env bash
set -euo pipefail

# Runs the launcher icon generator with a Pillow-capable interpreter. Build
# hosts whose system python3 already imports PIL (developer Macs) are used
# directly; otherwise a private virtual environment under the Gradle project
# cache is bootstrapped once, so CI runners and clean machines need no global
# package installation. Safe to invoke concurrently (app + Wear tasks).

script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
generator="$script_dir/generate-launcher-icons.py"
venv="${LAUNCHER_ICON_VENV:-$script_dir/../.gradle/launcher-icon-venv}"

if [[ "${LAUNCHER_ICON_FORCE_VENV:-}" != "1" ]] && python3 -c 'import PIL' >/dev/null 2>&1; then
    exec python3 "$generator" "$@"
fi

bootstrap_venv() {
    local staging lock i
    staging=$(mktemp -d "${venv}.staging.XXXXXX")
    python3 -m venv "$staging/venv"
    "$staging/venv/bin/python" -m pip install --quiet --disable-pip-version-check pillow
    lock="${venv}.lock"
    if mkdir "$lock" 2>/dev/null; then
        [[ -x "$venv/bin/python" ]] || mv "$staging/venv" "$venv"
        rmdir "$lock"
    fi
    rm -rf "$staging"
}

if [[ ! -x "$venv/bin/python" ]]; then
    bootstrap_venv
fi
# Wait out a concurrent bootstrap (lock presence), bounded at ~60s.
for _ in $(seq 1 300); do
    [[ -x "$venv/bin/python" || ! -d "${venv}.lock" ]] && break
    sleep 0.2
done
[[ -x "$venv/bin/python" ]] || { echo "launcher icon venv bootstrap failed: $venv" >&2; exit 1; }

exec "$venv/bin/python" "$generator" "$@"
