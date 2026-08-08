# Offline audio frontend A/B

This directory is an uncommitted experiment. It compares the current commit's
`RawLightDenoiser` modes without modifying application production sources.

## Inputs

Place the captured WAV files in one directory:

```text
raw_4ch_1786194763609.wav
raw_4ch_1786194978795.wav
ssp_mono_1786194763609.wav
ssp_mono_1786194978795.wav
```

The run used `/home/viadmin/Документы/voice_capture_2026-08-08`.

## Reproduce

From the repository root:

```bash
./android/gradlew -p android :app:testDebugUnitTest --tests 'ru.tander.smart_glasses.voice.AlignedFourChannelMixerTest' --tests 'ru.tander.smart_glasses.voice.RawLightDenoiserTest'
flutter test
flutter analyze
git diff --check

artifacts/audio_frontend_ab/scripts/run_kotlin_denoiser.sh \
  /absolute/path/raw_4ch_1786194763609.wav \
  /absolute/path/raw_4ch_1786194978795.wav

python3 artifacts/audio_frontend_ab/scripts/analyze_audio.py \
  --input-dir /absolute/path/to/captures \
  --output-dir artifacts/audio_frontend_ab
python3 artifacts/audio_frontend_ab/scripts/analyze_channel_delays.py \
  /absolute/path/to/captures \
  artifacts/audio_frontend_ab/channel_delay_windows.csv

python3 -m pip install --target artifacts/audio_frontend_ab/python_deps vosk==0.3.45
unzip -q -o assets/vosk-model-small-ru-0.22.zip -d artifacts/audio_frontend_ab/model
python3 artifacts/audio_frontend_ab/scripts/replay_vosk.py \
  --model artifacts/audio_frontend_ab/model/vosk-model-small-ru-0.22 \
  --audio-dir /absolute/path/to/captures \
  --output-dir artifacts/audio_frontend_ab
```

`RawDenoiserWavRunner.kt` is compiled with the repository's current
`AlignedFourChannelMixer.kt` and `RawLightDenoiser.kt`; it does not reimplement
their DSP in Python. It feeds exactly 2048 input bytes per call, preserves one
denoiser per recording, zero-pads only a final partial frame, and trims the
mono result to the original frame count.

`replay_vosk.py` uses the bundled model and a production-derived menu grammar.
It uses Vosk Python 0.3.45, while the Android application depends on Vosk
Android 0.3.75. Treat ASR findings as offline evidence, not an Android-device
certification.
