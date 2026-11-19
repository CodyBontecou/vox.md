#!/usr/bin/env bash
# Side-effect-free Google Play phone-track payload policy. Network mutation belongs exclusively to
# the protected Android release workflows.

play_phone_policy_fail() { printf 'Google Play phone policy: %s\n' "$*" >&2; return 1; }

play_phone_assert_version_code() {
  local code=$1
  [[ "$code" =~ ^[1-9][0-9]*$ ]] && (( code < 1000000 )) \
    || play_phone_policy_fail "phone versionCode must be between 1 and 999999: $code"
}

# Wear shares md.vox.android with the phone. wear/build.gradle.kts derives its code as the phone
# code + 1,000,000, so the two form factors can never claim the same versionCode.
play_wear_assert_version_code() {
  local code=$1
  [[ "$code" =~ ^[1-9][0-9]*$ ]] && (( code > 1000000 && code < 2000000 )) \
    || play_phone_policy_fail "Wear versionCode must be between 1000001 and 1999999: $code"
}

play_assert_version_code() {
  local form_factor=$1 code=$2
  case "$form_factor" in
    phone) play_phone_assert_version_code "$code" ;;
    wear) play_wear_assert_version_code "$code" ;;
    *) play_phone_policy_fail "unsupported form factor: $form_factor" ;;
  esac
}

# Optional fifth argument selects the form factor whose versionCode range applies (default phone).
play_phone_release_payload() {
  local code=$1 status=$2 language=$3 notes_file=$4 form_factor=${5:-phone}
  play_assert_version_code "$form_factor" "$code" || return
  case "$status" in completed|draft) ;; *) play_phone_policy_fail "unsupported release status: $status"; return ;; esac
  [[ -n "$language" && -s "$notes_file" ]] \
    || play_phone_policy_fail 'release-note language and non-empty file are required' || return
  jq -nc --arg code "$code" --arg status "$status" --arg language "$language" \
    --rawfile notes "$notes_file" '{
      releases:[{
        versionCodes:[$code],
        status:$status,
        releaseNotes:[{language:$language,text:($notes | sub("\\n+$"; ""))}]
      }]
    }'
}

play_phone_validate_track_response() {
  local response_file=$1 code=$2 status=$3
  jq -e --arg code "$code" --arg status "$status" '
    (.releases | length == 1) and
    .releases[0].status == $status and
    .releases[0].versionCodes == [$code]
  ' "$response_file" >/dev/null \
    || play_phone_policy_fail "track response does not contain only $code/$status"
}

play_phone_select_release() {
  local source_file=$1 code=$2
  jq -ce --arg code "$code" '
    first(.releases[]? | select(any(.versionCodes[]?; tostring == $code)))
  ' "$source_file"
}

play_phone_promotion_payload() {
  local source_file=$1 destination=$2 code=$3 output=$4 release
  [[ "$destination" == production ]] \
    || play_phone_policy_fail "phone destination must be production: $destination" || return
  play_phone_assert_version_code "$code" || return
  release=$(play_phone_select_release "$source_file" "$code") \
    || play_phone_policy_fail "source release $code is missing" || return
  printf '%s' "$release" | jq -ce --arg code "$code" --arg track "$destination" '
    .versionCodes = [$code]
    | .status = "completed"
    | del(.userFraction, .countryTargeting, .inAppUpdatePriority)
    | {track:$track, releases:[.]}
  ' >"$output"
  jq -e --arg code "$code" --arg track "$destination" '
    .track == $track and (.releases | length == 1) and
    .releases[0].status == "completed" and .releases[0].versionCodes == [$code]
  ' "$output" >/dev/null || play_phone_policy_fail 'production payload postcondition failed'
}
