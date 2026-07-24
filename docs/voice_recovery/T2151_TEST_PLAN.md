# T2151 Voice Recovery Test Plan

All checks in this document require a physical T2151 and remain `DEVICE_PENDING` until their evidence is recorded in `IMPLEMENTATION_STATUS.md`. The profile selection code, voice state/overlay integration, and debug APK build are complete; this plan verifies their behavior on the device.

## Preparation

1. Build the APK with `./tool/build_voice_recovery_apk.sh t2151` and install `build/app/outputs/flutter-apk/app-debug.apk`.
2. Capture `adb logcat` filtered by `VoiceCapture`, `WearVoiceSession`, `AudioStreamService`, `SpeechRecognitionService`, and the Android bridge.
3. Record the complete `[VoiceBuild]` line, device build, Android SDK, selected voice profile, audio source, capture ID, routed input device, and session diagnostics. Reject results whose `gitDirty` or `sourcePatchSha` do not match the tested APK record.

## Audio Source A/B Matrix

Build and test each profile under the same cold-start, resume, silencing, and long-run scenarios. Do not change the default profile based on a single run.

| Profile dart-define | Android source | Intended comparison |
|---|---|---|
| `VOICE_DEVICE_PROFILE=t2151` | `voiceCommunication` | Baseline T2151 profile. |
| `VOICE_DEVICE_PROFILE=t2151_voice_recognition` | `voiceRecognition` | Compare speech capture after resume. |
| `VOICE_DEVICE_PROFILE=t2151_microphone` | `mic` | Compare raw microphone route behavior. |

All three profile mappings are unit-tested. The debug APK has been built with `VOICE_DEVICE_PROFILE=t2151`; build and test the other two profiles before comparing results.

## Scenarios

1. Perform 50-100 cold starts; remain silent during every startup.
2. Perform 50-100 background-to-resume cycles.
3. Lock and unlock the screen.
4. Open and dismiss the notification shade.
5. Exercise permission and system-dialog windows.
6. Capture the microphone with another app, then return it to the application.
7. Connect and disconnect each supported audio device.
8. Run continuously for 8-12 hours.
9. Send several dozen supported voice commands after each recovery.
10. Verify the phone overlay for preparing, reconnecting, unavailable, and ready states.
11. Verify the glasses overlay for the same states.
12. Verify the underlying wear screen is retained while the overlay changes.
13. Recreate the glasses Presentation/secondary Flutter engine while an overlay is visible and verify it reappears.
14. Verify logs never show two active recorder instances for the same process.
15. Compare each configured audio-source profile under identical scenarios.
16. Save routed-device, session, source, and silencing diagnostics for every observed recovery.

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
