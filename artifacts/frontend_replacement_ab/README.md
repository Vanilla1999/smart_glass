# Frontend replacement offline A/B

This experiment compares mutually exclusive microphone frontends on the same
four-channel UAC4 recordings. It deliberately does **not** run WebRTC NS after
the existing legacy denoiser.

Candidates:

- each individual raw channel (`raw_ch0` ... `raw_ch3`);
- raw channel pairs (`raw_pair01`, `raw_pair12`, `raw_pair13`, `raw_pair23`);
- current raw average of channels 1..3 (`raw_mix123`);
- the same mix with the production 80 Hz high-pass only (`hpf80_mix123`);
- current reference `ssp_mono` (`legacy_reference`);
- WebRTC NS low/moderate applied directly to `raw_mix123`;
- dry/wet blends: 75/25 and 50/50 enhanced/raw for low and moderate.

The experiment has two stages:

1. Generate full-length mono frontend WAVs from the same raw recording.
2. Replay identical fixed time windows through a fresh Vosk recognizer per
   `(recording, window, frontend, recognizer mode)`.

The window builder merges old disputed windows but also adds independent
uniform control windows to reduce selection bias.

Generated WAVs, models and large JSONL timelines are ignored.
