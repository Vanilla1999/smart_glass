#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  tool/voice_replay/run_full_continuous.sh <wav> <report-log> [device-id]
USAGE
  exit 64
}

[[ $# -ge 2 && $# -le 3 ]] || usage
wav_input=$1
report_log=$2
device_id=${3:-}
android_log="${report_log%.log}.android.log"
device_log="${report_log%.log}.device.log"
logcat_pid=

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
fixture_rel="$fixture_dir/current_continuous_$$.wav"
mkdir -p "$fixture_dir" "$(dirname -- "$report_log")"
cp -- "$wav" "$fixture_rel"

wav_sha256=$(sha256sum -- "$wav" | cut -d' ' -f1)
wav_bytes=$(stat -c '%s' -- "$wav")

cleanup() {
  if [[ -n "$logcat_pid" ]]; then
    kill "$logcat_pid" 2>/dev/null || true
    wait "$logcat_pid" 2>/dev/null || true
  fi
  rm -f -- "$fixture_rel"
}
trap cleanup EXIT

adb_args=()
if [[ -n "$device_id" ]]; then
  adb_args+=( -s "$device_id" )
fi

capture_device_state() {
  local stage=$1
  {
    printf 'VOICE_REPLAY_DEVICE_STATE stage=%s capturedAt=%s\n' \
      "$stage" "$(date --iso-8601=seconds)"
    adb "${adb_args[@]}" shell dumpsys cpuinfo
    adb "${adb_args[@]}" shell dumpsys meminfo ru.tander.smart_glasses
    adb "${adb_args[@]}" shell dumpsys battery
    adb "${adb_args[@]}" shell dumpsys thermalservice
  } >> "$device_log" 2>&1
}

flutter_args=(
  --dart-define="VOICE_REPLAY_WAV_ASSET=$fixture_rel"
  --dart-define="VOICE_REPLAY_CASE=continuous"
)
if [[ -n "$device_id" ]]; then
  flutter_args+=( -d "$device_id" )
fi

: > "$android_log"
: > "$device_log"
adb "${adb_args[@]}" logcat -c
capture_device_state before
adb "${adb_args[@]}" logcat -v epoch > "$android_log" 2>&1 &
logcat_pid=$!

set +e
{
  printf 'VOICE_REPLAY_RECORDING sha256=%s bytes=%s source=%s\n' \
    "$wav_sha256" "$wav_bytes" "$(basename -- "$wav")"
  fvm flutter test \
    integration_test/voice_recording_replay_test.dart \
    "${flutter_args[@]}"
} 2>&1 | tee "$report_log"
flutter_status=${PIPESTATUS[0]}
set -e

capture_device_state after
exit "$flutter_status"
