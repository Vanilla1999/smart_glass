#!/usr/bin/env bash
set -euo pipefail

readonly output_dir="build/app/outputs/flutter-apk/voice-profiles"
readonly profiles=(
  "t2151"
  "t2151_voice_recognition"
  "t2151_microphone"
)

mkdir -p "$output_dir"

for profile in "${profiles[@]}"; do
  fvm flutter build apk --release \
    --dart-define="VOICE_DEVICE_PROFILE=$profile"
  cp "build/app/outputs/flutter-apk/app-release.apk" \
    "$output_dir/app-release-$profile.apk"
done

printf 'Built release APKs in %s\n' "$output_dir"
