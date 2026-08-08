#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
output_dir="$repo_root/artifacts/audio_frontend_ab"
sources=(
  "$repo_root/android/app/src/main/kotlin/ru/tander/smart_glasses/voice/AlignedFourChannelMixer.kt"
  "$repo_root/android/app/src/main/kotlin/ru/tander/smart_glasses/voice/RawLightDenoiser.kt"
  "$repo_root/artifacts/audio_frontend_ab/scripts/RawDenoiserWavRunner.kt"
)

kotlinc "${sources[@]}" -include-runtime -d "$output_dir/raw-denoiser-runner.jar"
for raw in "$@"; do
  kotlin -classpath "$output_dir/raw-denoiser-runner.jar" audiofrontendab.RawDenoiserWavRunnerKt "$raw" "$output_dir"
done
