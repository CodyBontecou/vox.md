#!/usr/bin/env bash
# Credential-free Play listing validation. Fails closed on missing or overlong
# fields so an incomplete listing can never reach the release workflow.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
listing="$script_dir/../play-console/listing"

fail() { printf 'Play listing validation: %s\n' "$*" >&2; exit 1; }

[[ -f "$listing/en-US/title.txt" ]] || fail 'en-US title is missing'
[[ -f "$listing/en-US/short-description.txt" ]] || fail 'en-US short description is missing'
[[ -f "$listing/en-US/full-description.txt" ]] || fail 'en-US full description is missing'

title=$(tr -d '\n' <"$listing/en-US/title.txt")
short=$(tr -d '\n' <"$listing/en-US/short-description.txt")
full=$(cat "$listing/en-US/full-description.txt")

[[ ${#title} -ge 3 && ${#title} -le 30 ]] || fail "title must be 3-30 characters, found ${#title}"
[[ ${#short} -ge 10 && ${#short} -le 80 ]] || fail "short description must be 10-80 characters, found ${#short}"
[[ ${#full} -ge 80 && ${#full} -le 4000 ]] || fail "full description must be 80-4000 characters, found ${#full}"

for notes in "$listing"/en-US/release-notes/en-US/*.txt; do
  [[ -s "$notes" ]] || fail "release notes are empty: $notes"
  notes_length=$(cat "$notes" | tr -d '\n' | wc -c | tr -d ' ')
  (( notes_length <= 500 )) || fail "release notes exceed 500 characters: $notes"
done

printf 'Play listing validation passed: %s\n' "$listing"
