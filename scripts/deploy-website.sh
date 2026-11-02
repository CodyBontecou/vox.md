#!/bin/sh
set -eu

PATH="$HOME/.local/bin:$PATH"
export PATH

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

SITE_BUILD=$(mktemp -d "${TMPDIR:-/tmp}/vox-website.XXXXXX")
trap 'rm -rf "$SITE_BUILD"' EXIT HUP INT TERM
python3 "$REPO_ROOT/scripts/build-website.py" "$SITE_BUILD/site"

wrangler pages deploy "$SITE_BUILD/site" --project-name voxboard "$@"

if command -v indexnow >/dev/null 2>&1; then
  if ! indexnow submit-sitemap vox.isolated.tech --recent-days 7 --confirm; then
    printf '%s\n' 'warning: production deployed, but IndexNow notification failed' >&2
  fi
else
  printf '%s\n' 'warning: indexnow CLI not found; production deployed without URL notification' >&2
fi
