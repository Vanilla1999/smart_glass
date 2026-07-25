# Final T2151 Remediation Plan

## Baseline

- Branch: `main`
- HEAD: `9d0273daa6312e451e8b3300e5331d47d4023f8b`
- Worktree: clean before this remediation.
- Baseline commands: `git status --short`, `git branch --show-current`, `git rev-parse HEAD`, `git log -5 --oneline`, `git diff --check`.

## Operating Rules

- Work from the captured `main` HEAD; do not use historical SHA values as evidence.
- Do not push, rewrite Git history, or remove existing wear flows, commands, screens, Vosk grammar, or secondary-display behavior.
- Mark device-only claims as `DEVICE_PENDING` until T2151 evidence exists.
- After each completed implementation item, perform a focused review. Apply one directly related correction when the review finds a defect; otherwise record that no correction was needed.

## P0 Correctness

1. Remove UI-route-triggered microphone restarts and rename the profile capability to native-audio-route semantics.
2. Make application lifecycle explicit: `inactive` retains active UI; only `hidden` and `paused` arm resume recovery; `resumed` uses one single-flight restart; `detached` cancels all voice work.
3. Make navigation delivery transactional. Each pending navigation request has an identity; delivery is single-flight and remains pending until a matching router acknowledgement. The existing flow/glasses projection remains optimistic to preserve screen-action behavior. Inactive requests are latest-wins.
4. Validate the current capture before publishing `ready`, including current capture epoch, recorder state, fresh PCM, no stream termination, and no capture silencing.
5. Give restart/retry/health checks one owner with cancellation and lifecycle guards.
6. Move zero-PCM thresholds and recovery policy into `VoiceDeviceProfile`; never treat low RMS as a fault.
7. Suppress a final command only when it equals a recently emitted partial command.

## P1 Responsiveness

1. Keep local focus updates synchronous and make glasses projection asynchronous.
2. Add a revisioned latest-wins selection patch channel, with full-payload fallback that cannot block the command queue.
3. Limit secondary-engine rebuilding to selected-list-item updates.
4. Use a short/jump voice-focus path and a programmatic-scroll feedback guard.
5. Add profile-specific PCM buffer sizing, diagnostics, and conservative T2151 A/B settings.
6. Warm Vosk model and command recognizer before authorization without blocking `runApp`; defer free-text recognizer creation until needed.

## P2 UVC Recovery

1. Select USB/UVC input deterministically before every recorder start and reacquire it after reattach.
2. Disable Bluetooth SCO management for T2151 USB/UVC profiles unless device validation proves it necessary.
3. Add typed native AudioDeviceCallback events and bind monitoring to native recording session data where the platform/plugin permits it.
4. Handle USB removal as waiting/reconnect, and automatically restart after expected USB input reappears and the HAL settles.
5. Implement profile-gated three-level UVC recovery. Physical reset and camera/audio composite recovery remain disabled until validated.
6. Investigate a privileged USB reset API without claiming a reset exists if the T2151 firmware does not expose one.

## Tests And Verification

- Add targeted tests for P0 through P2 items that can run without hardware.
- Run format, dependency resolution, analyzer, full tests, targeted tests, Kotlin compilation, `git diff --check`, and the existing T2151 APK build script.
- Update `IMPLEMENTATION_STATUS.md` with factual commands/results and `T2151_TEST_PLAN.md` with the required device matrix and metrics.
- Verify hardware claims only on a connected T2151; otherwise retain `DEVICE_PENDING` or `BLOCKED` with the exact external reason.
