# Android Vosk voice replay

This harness replays a real post-frontend PCM16 mono/16 kHz WAV through the
production Dart packet decoder, `AudioStreamService`, the real Android Vosk
plugin/JNI scheduler, `SpeechRecognitionService`, `WearVoiceControlService`,
the production application dispatcher and `WearFlowController`.

It deliberately keeps WAV files outside Git because recordings can be large or
contain speech. The runner copies the selected recording into the declared
integration-test asset directory only for the duration of the command, and a
`.gitignore` rule prevents accidental commits.

Run either regression case on an Android debug device:

```bash
tool/voice_replay/run_android_fixture.sh availability /path/to/availability.wav DEVICE_ID
tool/voice_replay/run_android_fixture.sh back /path/to/back.wav DEVICE_ID
tool/voice_replay/run_android_fixture.sh yellow /path/to/yellow.wav DEVICE_ID
tool/voice_replay/run_android_fixture.sh unrecognized /path/to/unrecognized.wav DEVICE_ID
```

The recording must contain the complete utterance plus trailing silence. The
`availability`, `back`, and `yellow` cases require exactly one business action. The
`unrecognized` case requires no action and the complete `Не распознано` visible
then hidden feedback transition. Every case requires accepted production-format
acknowledgements for all PCM packets. The harness starts after
the hardware/vendor frontend; UAC4 capture, SSP processing and the physical
microphone still require a device smoke test.

Run a complete recording through one uninterrupted recognizer session and keep
the structured diagnostic trace:

```bash
tool/voice_replay/run_full_continuous.sh \
  /path/to/complete.wav \
  artifacts/voice_replay/complete.log \
  DEVICE_ID
```

The runner writes the external recording's SHA-256 and byte length to the log.
It also writes `<report>.android.log` with native scheduler/GC events and
`<report>.device.log` with before/after CPU, process-memory, battery and thermal
snapshots. Correlate Dart and Android Vosk stages by `operationId`.
Structured events include the current source-audio offset. Continuous mode
fails on rejected PCM acknowledgements or any terminal native replay timeout;
the checked-in gate then compares current admissions and completed deterministic
actions with the immutable recording manifest.

```bash
dart run tool/voice_replay/run_voice_replay_gate.dart \
  artifacts/voice_replay/recording_manifest_2026-08-11.json \
  artifacts/voice_replay/current-run
```

The log directory must contain `flutter_1786374027358.log`,
`flutter_1786374143173.log`, and `flutter_1786374322845.log`.

The manifest contains only recording identity and human annotations. Historical
Vosk output, parser decisions and business observations remain in
`ground_truth_events_2026-08-11.json` and are not used to score a current run.
Do not update the manifest from decoder output after a runtime change.
