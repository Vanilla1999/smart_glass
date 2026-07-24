#!/usr/bin/env bash
set -euo pipefail

profile="${1:-t2151}"
sha="$(git rev-parse HEAD)"
timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
patch_sha="$({ git diff --binary HEAD; git ls-files --others --exclude-standard | while IFS= read -r file; do sha256sum "$file"; done; } | sha256sum | cut -d ' ' -f 1)"

if test -n "$(git status --porcelain)"; then
  dirty=true
else
  dirty=false
fi

fvm flutter build apk --debug \
  --dart-define="GIT_SHA=$sha" \
  --dart-define="BUILD_TIMESTAMP=$timestamp" \
  --dart-define="GIT_DIRTY=$dirty" \
  --dart-define="SOURCE_PATCH_SHA=$patch_sha" \
  --dart-define="VOICE_DEVICE_PROFILE=$profile"

printf 'Voice recovery APK: sha=%s dirty=%s patch=%s profile=%s\n' \
  "$sha" "$dirty" "$patch_sha" "$profile"
