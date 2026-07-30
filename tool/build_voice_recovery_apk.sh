#!/usr/bin/env bash
set -euo pipefail

sha="$(git rev-parse HEAD)"
timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
patch_sha="$({ git diff --binary HEAD; git ls-files --others --exclude-standard | while IFS= read -r file; do sha256sum "$file"; done; } | sha256sum | cut -d ' ' -f 1)"
free_text_pipeline_mode="${WEAR_FREE_TEXT_PIPELINE_MODE:-}"

if test -n "$(git status --porcelain)"; then
  dirty=true
else
  dirty=false
fi

build_args=(
  --release
  --target-platform android-arm64
  --dart-define="GIT_SHA=$sha"
  --dart-define="BUILD_TIMESTAMP=$timestamp"
  --dart-define="GIT_DIRTY=$dirty"
  --dart-define="SOURCE_PATCH_SHA=$patch_sha"
)

if test -n "$free_text_pipeline_mode"; then
  build_args+=(
    --dart-define="WEAR_FREE_TEXT_PIPELINE_MODE=$free_text_pipeline_mode"
  )
fi

fvm flutter build apk "${build_args[@]}"

printf 'Native UAC4 release APK: sha=%s dirty=%s patch=%s freeTextMode=%s\n' \
  "$sha" "$dirty" "$patch_sha" \
  "${free_text_pipeline_mode:-asset/default}"
