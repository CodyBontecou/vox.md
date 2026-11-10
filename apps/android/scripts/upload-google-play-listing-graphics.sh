#!/usr/bin/env bash
# Replace the Play store listing graphics (feature graphic, phone and tablet screenshots) for one
# locale with the files under play-console/graphics. Touches no tracks, bundles or text fields.
#
#   PLAY_CONSOLE_KEY_PATH=/path/to/service-account.json \
#   CONFIRM_PLAY_LISTING_GRAPHICS=md.vox.android:en-US \
#   apps/android/scripts/upload-google-play-listing-graphics.sh
#
# Set PLAY_LISTING_DRY_RUN=1 to validate the edit without committing it.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
graphics=${PLAY_GRAPHICS_ROOT:-"$script_dir/../play-console/graphics"}
key=${PLAY_CONSOLE_KEY_PATH:-}
token=${PLAY_ACCESS_TOKEN:-}
package=${PLAY_PACKAGE_NAME:-md.vox.android}
locale=${PLAY_LISTING_LOCALE:-en-US}
dry_run=${PLAY_LISTING_DRY_RUN:-}
confirmation=${CONFIRM_PLAY_LISTING_GRAPHICS:-}

fail() { printf 'Play listing graphics: %s\n' "$*" >&2; exit 1; }

# imageType → source files, in upload order.
declare -a types=(featureGraphic phoneScreenshots sevenInchScreenshots tenInchScreenshots)
files_for() {
  case $1 in
    featureGraphic) printf '%s\n' "$graphics/feature-graphic-1024x500.png" ;;
    phoneScreenshots) ls "$graphics"/screenshots/phone/*.png ;;
    sevenInchScreenshots) ls "$graphics"/screenshots/tablet-7/*.png ;;
    tenInchScreenshots) ls "$graphics"/screenshots/tablet-10/*.png ;;
  esac
}

for type in "${types[@]}"; do
  n=0
  while IFS= read -r f; do [[ -s "$f" ]] || fail "missing $f"; n=$((n + 1)); done < <(files_for "$type")
  [[ $n -ge 1 && $n -le 8 ]] || fail "$type needs 1–8 images, found $n"
  [[ $type != phoneScreenshots || $n -ge 2 ]] || fail 'Play requires at least 2 phone screenshots'
done

[[ -n "$token" || ( -n "$key" && -r "$key" ) ]] \
  || fail 'PLAY_ACCESS_TOKEN or a readable PLAY_CONSOLE_KEY_PATH is required'
[[ -n "$dry_run" || "$confirmation" == "$package:$locale" ]] \
  || fail "set CONFIRM_PLAY_LISTING_GRAPHICS=$package:$locale (or PLAY_LISTING_DRY_RUN=1)"
for command in curl jq openssl; do command -v "$command" >/dev/null || fail "$command is required"; done

base64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
api="https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$package"
upload_api="https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/$package"
work=$(mktemp -d)
private_key=''
edit_id=''
committed=false
cleanup() {
  [[ -z "$private_key" ]] || rm -f "$private_key"
  if [[ -n "$edit_id" && "$committed" != true && -n "$token" ]]; then
    curl -fsS -X DELETE -H "Authorization: Bearer $token" "$api/edits/$edit_id" >/dev/null 2>&1 || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

if [[ -z "$token" ]]; then
  private_key=$(mktemp)
  jq -er .private_key "$key" >"$private_key"
  chmod 600 "$private_key"
  now=$(date +%s)
  header=$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | base64url)
  claims=$(jq -nc --arg iss "$(jq -er .client_email "$key")" --arg aud "$(jq -er .token_uri "$key")" \
    --argjson iat "$now" \
    '{iss:$iss,scope:"https://www.googleapis.com/auth/androidpublisher",aud:$aud,iat:$iat,exp:($iat+1200)}' \
    | base64url)
  signature=$(printf '%s' "$header.$claims" | openssl dgst -sha256 -sign "$private_key" | base64url)
  curl --fail-with-body -sS --max-time 30 -o "$work/token.json" \
    --data-urlencode "assertion=$header.$claims.$signature" \
    --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer' \
    "$(jq -er .token_uri "$key")" || fail "OAuth token exchange failed: $(cat "$work/token.json" 2>/dev/null)"
  token=$(jq -er .access_token "$work/token.json") || fail 'OAuth response omitted access_token'
fi
auth=(-H "Authorization: Bearer $token")

call() { # method url [curl args...] — prints body, fails with Play's error message
  local method=$1 url=$2; shift 2
  local out="$work/resp.json" http
  http=$(curl -sS --max-time 120 -X "$method" "${auth[@]}" "$@" "$url" -o "$out" -w '%{http_code}') || true
  if [[ ! "$http" =~ ^2 ]]; then
    fail "$method ${url#"$api"} → HTTP $http: $(jq -r '.error.message // .' "$out" 2>/dev/null | head -c 500)"
  fi
  cat "$out"
}

edit_id=$(call POST "$api/edits" -H 'Content-Type: application/json' -d '{}' | jq -er .id)
printf 'Opened edit %s for %s (%s)\n' "$edit_id" "$package" "$locale"

for type in "${types[@]}"; do
  call DELETE "$api/edits/$edit_id/listings/$locale/$type" >/dev/null
  while IFS= read -r f; do
    call POST "$upload_api/edits/$edit_id/listings/$locale/$type?uploadType=media" \
      -H 'Content-Type: image/png' --data-binary "@$f" >/dev/null
    printf '  %-22s %s\n' "$type" "${f#"$graphics/"}"
  done < <(files_for "$type")
done

call POST "$api/edits/$edit_id:validate" -H 'Content-Type: application/json' -d '' >/dev/null
if [[ -n "$dry_run" ]]; then
  printf 'Dry run: edit validated; discarding it without committing.\n'
  exit 0
fi
call POST "$api/edits/$edit_id:commit" -H 'Content-Type: application/json' -d '' >/dev/null
committed=true
printf 'Committed. Listing graphics for %s (%s) replaced.\n' "$package" "$locale"
