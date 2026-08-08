# Offline WebRTC NS A/B

This experiment applies WebRTC Audio Processing noise suppression to the existing
mono baseline (`ssp_mono_*.wav`) without changing Android production sources.

It compares:

- baseline: no additional processing;
- NS low: WebRTC policy 0;
- NS moderate: WebRTC policy 1;
- NS high: WebRTC policy 2;
- NS very-high: WebRTC policy 3 (generated for evidence, not recommended for production by default).

AEC, AGC and VAD are disabled. Input and output are PCM16 LE, mono, 16 kHz.
WebRTC APM is fed exactly 10 ms (160 sample / 320 byte) frames. A final partial
frame is zero-padded and the output is trimmed back to the original sample count.

## Dependency

The runner expects the Python module `webrtc_audio_processing` exposing
`AudioProcessingModule`.

Prefer a Python 3.10 or 3.11 virtual environment because the available binding
is old and may not build on Python 3.14.

Example:

```bash
python3.11 -m venv artifacts/webrtc_ns_ab/.venv
source artifacts/webrtc_ns_ab/.venv/bin/activate
python -m pip install --upgrade pip setuptools wheel
python -m pip install webrtc-audio-processing==0.1.3 vosk==0.3.45
```

If the package cannot build, do not silently substitute spectral gating,
RNNoise, FFmpeg filters or Android `NoiseSuppressor`; report the blocker.

## Generate NS WAV files

```bash
python artifacts/webrtc_ns_ab/scripts/apply_webrtc_ns.py \
  --input-dir /absolute/path/to/captures \
  --output-dir artifacts/webrtc_ns_ab/outputs
```

Generated names:

```text
baseline_ssp_1786194763609.wav
webrtc_ns_low_1786194763609.wav
webrtc_ns_moderate_1786194763609.wav
webrtc_ns_high_1786194763609.wav
webrtc_ns_very_high_1786194763609.wav
```

and the same set for `1786194978795`.

## Replay through Vosk

```bash
python artifacts/webrtc_ns_ab/scripts/replay_vosk_matrix.py \
  --model /absolute/path/vosk-model-small-ru-0.22 \
  --audio-dir artifacts/webrtc_ns_ab/outputs \
  --output-dir artifacts/webrtc_ns_ab/outputs
```

The scripts write a manifest, WAV metrics, full ASR event timeline and summary.
Do not commit generated model files, Python dependencies or output WAV files.
