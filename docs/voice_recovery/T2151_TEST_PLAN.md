# T2151 Voice Recovery Test Plan

## Strict profile update

Verify UVC selection, absence of built-in-microphone fallback, 1500 ms initial
grace, one recreate, and 3000 ms second-attempt grace. Default release builds
must not create WAV files; use `VOICE_CAPTURE_WAV_DIAGNOSTICS=true` only for
diagnostic APKs. All hardware evidence remains `DEVICE_PENDING`.

All checks in this document require a physical T2151 and remain `DEVICE_PENDING` until their evidence is recorded in `IMPLEMENTATION_STATUS.md`. The profile selection code, voice state/overlay integration, and debug APK build are complete; this plan verifies their behavior on the device.

## Preparation

1. Build the three release APKs with `./tool/build_t2151_voice_profiles_release.sh`.
2. Install one APK at a time from `build/app/outputs/flutter-apk/voice-profiles/`.
3. Capture `adb logcat` filtered by `VoiceCapture`, `WearVoiceSession`, `AudioStreamService`, `SpeechRecognitionService`, and the Android bridge.
4. Record the device build, Android SDK, selected voice profile, audio source, capture ID, routed input device, VAD event values, and session diagnostics.

## Audio Source A/B Matrix

Build and test each profile under the same cold-start, resume, silencing, and long-run scenarios. Do not change the default profile based on a single run.

| Profile dart-define | Android source | Intended comparison |
|---|---|---|
| `VOICE_DEVICE_PROFILE=t2151` | `voiceCommunication` | Baseline T2151 profile. |
| `VOICE_DEVICE_PROFILE=t2151_voice_recognition` | `voiceRecognition` | Compare speech capture after resume. |
| `VOICE_DEVICE_PROFILE=t2151_microphone` | `mic` | Compare raw microphone route behavior. |

All three profile mappings are unit-tested. Test every profile before choosing a T2151 default.

## Scenarios

1. Perform 50 cold starts; remain silent during every startup.
2. Perform 100 background-to-resume cycles.
3. Generate 20 `inactive`-only events, including 20 notification-shade interactions, and verify no restart.
4. Perform 20 lock/unlock cycles.
5. Capture the microphone with another app, then return capture.
6. Perform 20 USB/UVC unplug/replug cycles; record old and new device IDs.
7. Verify automatic voice recovery after every expected UVC reattach, then verify the manual retry fallback.
8. Exercise exact-zero PCM, profile-gated route bounce, and camera-plus-audio recovery only when each experiment is enabled.
9. Run continuously for 8-12 hours.
10. Send 100 `вверх`, 100 `вниз`, 50 availability commands, and rapid mixed up/down series.
11. Verify phone and glasses remain on the same screen after every navigation and recovery.
12. Verify phone and glasses overlays for preparing, reconnecting, unavailable, waiting/reconnect, and ready states without replacing the wear screen.
13. Recreate the glasses Presentation/secondary Flutter engine while an overlay is visible and verify it reappears.
14. Verify logs never show two active recorder instances for the same process.
15. Compare each configured audio-source profile under identical scenarios.
16. Save routed-device, session, source, silencing diagnostics, and recovery result for every observed recovery.

## Metrics

- ASR partial latency p50/p95.
- Command dispatch p50/p95.
- Phone focus-frame p50/p95.
- Glasses receive-to-frame p50/p95.
- Authorization-to-ready and app-start-to-model-ready.
- Recovery duration, recorder recreations, duplicate restart count, route mismatch count, zero-PCM incidents, and USB-reattach success rate.

## Partial-Policy Safety Check

This check remains `DEVICE_PENDING` until repeated with the patched release APK:

1. On the menu, say `вверх` 30 times and `вниз` 30 times.
2. Say `доступность` 20 times.
3. Say `назад` 20 times on a screen where back is registered.
4. Repeat only `вверх` and `вниз` at different rates and volumes.
5. Add unrelated speech and store background noise.

Record each utterance whose provisional partial differs from its final result.
`up` and `down` must still execute from partial. No route-changing command may
have `source=stable_partial`; an isolated `доступность` or `назад` partial must
not change the screen. Route and state changes may occur only from a natural
endpoint result or VAD-silence `streamFinal`.

Count false endpoint commands separately. In particular, this patch does not
fix the known false `streamFinal="выбрать"`. A second acoustic verifier, phrase
hardening, and speaker gating are outside this check.

## Acceptance Criteria

- Silence and low RMS do not cause startup errors or restart loops.
- Startup does not require speech.
- Resume restores voice through exactly one coordinated recovery when required.
- Voice commands are not delivered while recovery or unavailability is displayed.
- Commands resume after a successful recovery.
- An initial failure continues retrying automatically.
- The overlay matches actual voice state and does not replace the active wear screen.
- `updateWearGlasses` does not hide a visible glasses overlay.
- A visible glasses overlay is reapplied after Presentation recreation.
- There are zero false startup errors from silence, zero UI-route restarts, zero parallel recorders, and zero commands outside `VoicePhase.ready`.
- `up`/`down` command handlers do not wait for glasses acknowledgement.
- Only `up` and `down` execute from partial; every other production command is
  endpoint-only and production `stableExactPartial` usage is zero.
- Ordinary low RMS never triggers recovery; no rapid restart loop occurs.
- USB reattach restores voice automatically once the native device-event path is implemented and validated.
