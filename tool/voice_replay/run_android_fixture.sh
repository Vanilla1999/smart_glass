#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  tool/voice_replay/run_android_fixture.sh <availability|back|yellow|unrecognized> <wav> [device-id]
USAGE
  exit 64
}

[[ $# -ge 2 && $# -le 3 ]] || usage
case_name=$1
wav_input=$2
device_id=${3:-}

case "$case_name" in
  availability|back|yellow|unrecognized) ;;
  *) usage ;;
esac
[[ -f "$wav_input" ]] || {
  echo "WAV not found: $wav_input" >&2
  exit 66
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/../.." && pwd)
wav_dir=$(cd -- "$(dirname -- "$wav_input")" && pwd)
wav="$wav_dir/$(basename -- "$wav_input")"
cd -- "$repo_root"

fixture_dir="integration_test/fixtures"
fixture_rel="$fixture_dir/current_${case_name}_$$.wav"
mkdir -p "$fixture_dir"
cp -- "$wav" "$fixture_rel"

cleanup() {
  rm -f -- "$fixture_rel"
}
trap cleanup EXIT

flutter_args=(
  --dart-define="VOICE_REPLAY_WAV_ASSET=$fixture_rel"
  --dart-define="VOICE_REPLAY_CASE=$case_name"
)
if [[ -n "$device_id" ]]; then
  flutter_args+=( -d "$device_id" )
fi

fvm flutter test \
  integration_test/voice_recording_replay_test.dart \
  "${flutter_args[@]}"
