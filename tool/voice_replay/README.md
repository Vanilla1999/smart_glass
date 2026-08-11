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

This mode has no ground-truth timeline. It reports observed Vosk-to-command,
admission, feedback and application-flow events without asserting which spoken
commands should be present.
