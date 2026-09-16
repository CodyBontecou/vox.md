#!/usr/bin/env bash
set -euo pipefail

# Diagnostics: name each API stage so a failure names its URL and body.
play_call() {
  local stage=$1; shift
  local body out rc
  out=$(mktemp)
  set +e
  body=$(curl -sS --max-time 60 "$@" -o "$out" 2>&1); rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    printf 'Phone Play promote: %s failed (curl rc=%s): %s\n' "$stage" "$rc" "$body" >&2
    head -c 400 "$out" >&2 2>/dev/null || true
    printf '\n' >&2
    rm -f "$out"
    return $rc
  fi
  cat "$out"
  rm -f "$out"
}

# Promotes an exact phone versionCode from Internal Testing to Production in one
# Play edit and proves the resulting review lifecycle. Mirrors the guarded
# semantics of upload-google-play-phone-release.sh: exact-code pinning, a
# confirmation string, single-shot commit, and postcondition polling.

script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
release_root=${PLAY_RELEASE_ROOT:-"$script_dir/.."}
cd "$release_root"

key=${PLAY_CONSOLE_KEY_PATH:-}
token=${PLAY_ACCESS_TOKEN:-}
package=${PLAY_PACKAGE_NAME:-md.vox.android}
version_code=${PHONE_VERSION_CODE:-}
confirmation=${CONFIRM_PLAY_PROMOTION:-}
expected_confirmation="$package:production:$version_code"
receipt=${PLAY_PROMOTE_RECEIPT_PATH:-}
locale=${PLAY_LISTING_LOCALE:-en-US}
release_notes=${PLAY_RELEASE_NOTES:-play-console/listing/$locale/release-notes/$locale/default.txt}

fail() { printf 'Phone Play promote: %s\n' "$*" >&2; exit 1; }

[[ -n "$token" || ( -n "$key" && -r "$key" ) ]] \
  || fail 'PLAY_ACCESS_TOKEN or a readable PLAY_CONSOLE_KEY_PATH is required'
[[ "$version_code" =~ ^[1-9][0-9]*$ ]] || fail "PHONE_VERSION_CODE is required: $version_code"
[[ "$confirmation" == "$expected_confirmation" ]] || fail "set CONFIRM_PLAY_PROMOTION=$expected_confirmation"
[[ -s "$release_notes" ]] || fail "release notes are missing: $release_notes"
for command in curl jq; do command -v "$command" >/dev/null || fail "$command is required"; done

base64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
private_key=''
work=$(mktemp -d)
edit_id=''
committed=false
api="https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$package"
cleanup() {
  [[ -z "$private_key" ]] || rm -f "$private_key"
  rm -rf "$work"
  if [[ -n "$edit_id" && "$committed" != true && -n ${token:-} ]]; then
    curl -fsS --retry 2 -X DELETE -H "Authorization: Bearer $token" \
      "$api/edits/$edit_id" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ -z "$token" ]]; then
  private_key=$(mktemp)
  jq -er .private_key "$key" >"$private_key"
  chmod 600 "$private_key"
  now=$(date +%s)
  header=$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | base64url)
  claims=$(jq -nc \
    --arg iss "$(jq -er .client_email "$key")" \
    --arg aud "$(jq -er .token_uri "$key")" \
    --argjson iat "$now" \
    '{iss:$iss,scope:"https://www.googleapis.com/auth/androidpublisher",aud:$aud,iat:$iat,exp:($iat+1200)}' | base64url)
  signature=$(printf '%s' "$header.$claims" | openssl dgst -sha256 -sign "$private_key" | base64url)
  token=$(curl -fsS --retry 3 --max-time 30 -sS \
    --data-urlencode "assertion=$header.$claims.$signature" \
    --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer' \
    "$(jq -er .token_uri "$key")" | jq -er .access_token) \
    || fail 'Google OAuth authentication failed before any Play request'
fi
auth=(-H "Authorization: Bearer $token")

# Reconcile: an identical production release means this promote already ran.
if curl -fsS --retry 2 --max-time 30 -sS "${auth[@]}" "$api/tracks/production/releases" \
    -o "$work/prod-before.json" 2>/dev/null \
  && jq -e --argjson code "$version_code" \
    'any(.releases[]?; any(.activeArtifacts[]?; (.versionCode | tonumber) == $code))' \
    "$work/prod-before.json" >/dev/null; then
  printf 'Production already contains %s; reconciled without another edit.\n' "$version_code"
  exit 0
fi

play_call "internal track query" "${auth[@]}" "$api/tracks/internal/releases" >"$work/internal.json" \
  || fail 'internal track query failed'
source_release=$(jq -ce --argjson code "$version_code" \
  'first(.releases[]? | select(any(.versionCodes[]?; (. | tonumber) == $code) or any(.activeArtifacts[]?; (.versionCode | tonumber) == $code))) // empty' \
  "$work/internal.json" 2>/dev/null) || true
[[ -n "$source_release" ]] || { printf 'internal track response: '; head -c 800 "$work/internal.json" >&2; printf '\\n'; fail "versionCode $version_code is not on the internal track"; }

edit_id=$(play_call "edit creation" -X POST "${auth[@]}" \
  -H 'Content-Type: application/json' -d '{}' "$api/edits" | jq -er .id) \
  || fail 'Play edit creation failed'

release_payload=$(printf '%s' "$source_release" | jq -ce --argjson code "$version_code" \
  --arg status "${PLAY_PROMOTE_STATUS:-draft}" \
  --arg language "$locale" --rawfile notes "$release_notes" '
  # Only writable fields: copy nothing else from the internal release object.
  {name: .name, versionCodes: [$code | tostring], status: $status,
   releaseNotes: [{language: $language, text: ($notes | sub("\\n+$"; ""))}]}
  | if .name == null or .name == "" then del(.name) else . end
')
play_call "production track update" -X PUT "${auth[@]}" \
  -H 'Content-Type: application/json' --data "$(jq -nc --argjson release "$release_payload" '{track: "production", releases: [$release]}')" \
  "$api/edits/$edit_id/tracks/production" >"$work/track-update.json"
jq -e --argjson code "$version_code" \
  '(.releases | length == 1) and any(.releases[0].versionCodes[]?; (. | tonumber) == $code)' \
  "$work/track-update.json" >/dev/null || { printf 'track-update response: '; head -c 600 "$work/track-update.json" >&2; printf '\n'; fail 'production track update did not contain only the promoted code'; }

play_call "edit validation" -X POST "${auth[@]}" \
  -H 'Content-Type: application/json' -d '' "$api/edits/$edit_id:validate" >"$work/validate.json" \
  || fail "Play rejected the promote edit at validation"

commit_response_received=true
set +e
commit_http=$(curl -sS --max-time 30 -X POST "${auth[@]}" -H 'Content-Type: application/json' \
  "$api/edits/$edit_id:commit?changesNotSentForReview=false&changesInReviewBehavior=ERROR_IF_IN_REVIEW" \
  --data '' -o "$work/commit.json" -w '%{http_code}')
commit_exit=$?
set -e
if [[ $commit_exit -ne 0 || ! "$commit_http" =~ ^2[0-9][0-9]$ ]]; then
  printf 'commit failed: curl_rc=%s http=%s body=' "$commit_exit" "${commit_http:-000}" >&2
  head -c 600 "$work/commit.json" >&2 2>/dev/null || true
  printf '\n' >&2
  fail 'promote commit was rejected'
fi
[[ $commit_exit -eq 0 ]] || commit_response_received=false

commit_visible=false
for _ in $(seq 1 24); do
  if curl -fsS --retry 2 --max-time 30 -sS "${auth[@]}" "$api/tracks/production/releases" \
      -o "$work/prod-after.json" \
    && jq -e --argjson code "$version_code" \
      'any(.releases[]?; any(.activeArtifacts[]?; (.versionCode | tonumber) == $code))' \
      "$work/prod-after.json" >/dev/null; then
    commit_visible=true
    break
  fi
  sleep 5
done
$commit_visible || fail 'production commit postcondition is absent'
committed=true
edit_id=''

for _ in $(seq 1 40); do
  curl -fsS --retry 3 --max-time 30 -sS "${auth[@]}" "$api/tracks/production/releases" \
    -o "$work/lifecycle.json"
  state=$(jq -r --argjson code "$version_code" '
    first(.releases[]? | select(any(.activeArtifacts[]?; (.versionCode | tonumber) == $code)) | .releaseLifecycleState) // empty' \
    "$work/lifecycle.json")
  case "$state" in
    RELEASE_LIFECYCLE_STATE_IN_REVIEW|RELEASE_LIFECYCLE_STATE_APPROVED_NOT_PUBLISHED|RELEASE_LIFECYCLE_STATE_PUBLISHED|RELEASE_LIFECYCLE_STATE_DRAFT)
      if [[ -n "$receipt" ]]; then
        mkdir -p "$(dirname "$receipt")"
        jq -n --argjson code "$version_code" --arg state "$state" \
          --arg aabTrack production --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
          '{schemaVersion:1,versionCode:$code,track:$aabTrack,lifecycleState:$state,commitResponseReceived:true,verifiedAtUtc:$at}' \
          >"$receipt"
      fi
      printf 'Promoted %s to production; review lifecycle: %s\n' "$version_code" "$state"
      exit 0
      ;;
  esac
  sleep 15
done
fail "production versionCode $version_code was not proven submitted for review"
