# T2151 Noisy Store Voice Validation Plan

Status: `PLANNED`

Related documents:

- `T2151_VOICE_HINT_UX_PLAN.md`
- `T2151_DYNAMIC_PARTIAL_PIPELINE_PLAN.md`
- `T2151_TEST_PLAN.md`
- `T2151_VOICE_RECOGNITION_ROLLOUT.md`

## 1. Objective

Validate that early voice feedback and dynamic constrained phrases reduce
latency without increasing false actions in a real store environment.

The validation must measure command behavior, dynamic free-text behavior,
progressive clarification, CPU stability and user-visible responsiveness.

## 2. Safety Principles

- A partial result may change focus only during the initial rollout.
- Final arbitration owns selection and navigation.
- Printing, database mutation and irreversible operations remain final-only.
- Every event is checked against capture, route, grammar, free-text and list
  revisions.
- Exactly one business intent is permitted per utterance.
- Barcode or another independent signal remains the product identity source.

## 3. Build Preconditions

Performance measurements are invalid unless all conditions are recorded:

- release or profile build type;
- commit SHA and dirty worktree fingerprint;
- device model and Android version;
- Vosk model checksum;
- `WEAR_FREE_TEXT_PIPELINE_MODE` value;
- endpoint and VAD parameters;
- active input device and channel configuration;
- denoiser, AGC, AEC and beamforming state;
- dynamic grammar phrase count;
- mock mode disabled;
- diagnostic WAV recording disabled unless the test explicitly measures it;
- device temperature and battery state at test start.

The application must log these values once per session.

## 4. Test Environments

Run the same scenario set in:

| Environment | Purpose |
|---|---|
| Quiet office | Recognition ceiling and deterministic baseline |
| Controlled playback | Repeatable A/B comparison |
| Store before opening | Real room reverberation and equipment noise |
| Normal store operation | Customers, coworkers, music and announcements |
| Noisiest known zone | Worst-case acceptance test |

Controlled playback must include target speech mixed with store noise at
approximately 15 dB, 10 dB and 5 dB SNR.

Store sound classes must include:

- background conversations;
- a coworker speaking near the operator;
- similar command words spoken by another person;
- music and public announcements;
- printers and scanners;
- ventilation and refrigeration;
- carts, baskets and impacts;
- feedback sounds emitted by the glasses or phone.

Recordings involving real customers require the applicable privacy and consent
process. Controlled reenactment is preferred for reusable automated evidence.

## 5. Speaker Coverage

The pilot set should contain at least five speakers when available.

Coverage:

- different voices and speaking volume;
- fast, normal and slow speech;
- different Russian accents;
- operator facing forward and turning the head;
- normal breathing and movement;
- mask or other store equipment when used operationally;
- repeated commands during a continuous shift-length session.

## 6. Scenario Matrix

### 6.1 Immediate fixed commands

Run at least 100 successful attempts per command and environment:

```text
up
down
```

Run at least 50 attempts per endpoint-only command and environment:

```text
back
select
print
availability
next page
previous page
```

Verify latency, misses, duplicate actions and false activation from background
speech.

### 6.2 Bold dynamic keys

Run at least 50 attempts for each representative key:

```text
white
yellow
mobile
one unique product word
one unique two-word phrase
one unique three-word phrase
```

Verify:

- first non-empty partial;
- first stable matching partial;
- focus update;
- final decision;
- selected item ID;
- final disagreement with preview;
- no partial business side effect.

### 6.3 Arbitrary multiword free-text

Use complete and incomplete name phrases:

```text
простоквашино
молоко простоквашино
домик в деревне
молоко домик отборное
```

Include word-order variation, `ё`/`е`, natural pauses and rejected unrelated
words.

### 6.4 Progressive clarification

Prepare candidate sets with:

- two matches;
- four matches;
- more than four matches;
- candidates sharing the first spoken word;
- candidates requiring a two-word differentiator;
- candidates with identical voice-relevant labels;
- candidates changing while clarification is open.

Verify:

- first phrase opens clarification only after final;
- second phrase filters the existing set;
- third phrase can filter again;
- unique result selects the correct original item;
- back restores the previous candidate set;
- bold phrases are recalculated after every step;
- unchanged query shows `Назовите точнее`;
- no-match query leaves the current candidates intact;
- stale or removed items are not selected.

### 6.5 Hard negatives

Run continuous audio containing:

- nearby speech unrelated to the application;
- command words used in ordinary conversation;
- words phonetically similar to `up`, `down`, `white` and `yellow`;
- partial item names that match several candidates;
- coughs, impacts and scanner beeps;
- silence and constant equipment noise.

Hard-negative evaluation must be reported in hours, not only utterance count.
An initial pilot requires at least one complete eight-hour equivalent. Longer
negative evidence is required before broad production rollout.

## 7. Required Timestamps

Capture the following timestamps for every utterance:

```text
native sample captured
PCM admitted by Dart
VAD start
first non-empty command partial
first non-empty free-text partial
first stable candidate
focus payload sent
focus frame rendered
VAD endpoint
command final
free-text final
arbitration decision
selection handler started
selection payload sent
selection frame rendered
```

Current `VAD_START -> result` metrics do not include physical sample age. Both
physical and Dart-visible latency must be reported.

## 8. Metrics

Report p50, p95 and p99 for:

- physical speech/sample to VAD start;
- VAD start to first partial;
- VAD start to stable candidate;
- stable candidate to focus frame;
- speech tail to VAD endpoint;
- endpoint to final decision;
- final decision to selection frame;
- total speech to focus;
- total speech to selection;
- grammar switch time;
- command and free-text queue delay;
- recognizer processing time.

Report reliability metrics:

- intended-command success rate;
- false activations per hour;
- false focus previews per hour;
- incorrect selections per 1000 attempts;
- missed commands per 100 attempts;
- duplicate intent count;
- stale event count;
- preview/final disagreement rate;
- clarification success rate;
- average utterances required for clarification;
- fallback and replay rate;
- dropped PCM frame count;
- recognizer timeout and recovery count.

Report device metrics:

- CPU;
- memory;
- GC frequency;
- device temperature;
- battery consumption;
- queue growth during a continuous session.

## 9. Experiment Sequence

### Experiment A: Current final-only baseline

Use the current endpoint-only dynamic behavior. Measure `up`, `down`, short
dynamic words, multiword names and clarification.

### Experiment B: Typed preview only

Connect context-safe partial events. Allow focus updates only. Keep final
selection unchanged.

Compare:

- time to first visible response;
- false preview rate;
- preview/final disagreement;
- command latency regression.

### Experiment C: Dynamic constrained keys

Add current-page bold keys to constrained grammar.

Compare:

- first partial latency;
- stable candidate latency;
- key accuracy;
- OOV rate;
- grammar switch cost;
- impact on fixed commands.

### Experiment D: Stability sweep

Replay identical PCM with stability delays:

```text
100 ms
150 ms
200 ms
250 ms
```

Choose the smallest value that satisfies false-preview and disagreement limits
in store noise.

### Experiment E: Endpoint sweep

After preview behavior is accepted, compare:

```text
500 ms
400 ms
300 ms
```

Measure truncated phrases, accidental utterance splitting, misses and false
finals. Do not globally reduce endpoint silence based only on quiet-room data.

### Experiment F: Audio front end

Compare one change at a time:

- current channel/denoiser path;
- best single UAC4 channel;
- alternate channel combination or beamforming;
- WebRTC VAD candidate configuration;
- optional noise suppression;
- AEC when output audio is active.

Do not stack processing stages before individual A/B evidence exists.

## 10. Provisional Acceptance Targets

These targets are product gates to validate, not claims about current behavior.

| Metric | Target |
|---|---:|
| `up`/`down` p50 to frame | at most 450 ms |
| `up`/`down` p95 to frame | at most 600 ms |
| bold-key p50 to focus frame | at most 600 ms |
| bold-key p95 to focus frame | at most 750 ms |
| optimized dynamic p95 to selection frame | at most 900 ms |
| arbitrary multiword p95 to selection/clarification | at most 1300 ms |
| duplicate intents | 0 |
| stale UI/business actions | 0 |
| irreversible action from partial | 0 |
| false business actions | 0 |
| false navigation actions | fewer than 1 per 8-hour equivalent |
| PCM drops | 0 |

Accuracy gates:

- bold keys: at least 95% correct in quiet conditions;
- bold keys: at least 90% correct in the accepted store-noise condition;
- final selected item: at least 95% correct after allowed clarification;
- clarification: at least 90% resolved within two additional utterances;
- `up`/`down` latency regression after enabling dynamic live processing: no more
  than 10% at p95.

If operational risk requires stricter limits, the product owner must replace
these provisional gates before rollout.

## 11. Rollout

### Phase 1: Instrumentation

- No behavior change.
- Collect quiet and controlled-noise baseline.
- Verify complete timestamps and build fingerprint.

### Phase 2: Preview shadow

- Compute stable partial candidates.
- Log intended focus changes without showing them.
- Compare preview with final decisions.

### Phase 3: Visible focus preview

- Enable preview for internal users.
- Keep selection final-only.
- Collect store-shift evidence.

### Phase 4: Dynamic grammar pilot

- Enable bold constrained keys for selected screens.
- Keep arbitrary free-text and replay fallback.
- Monitor latency, OOV and false activations.

### Phase 5: Endpoint optimization

- Enable only the accepted endpoint value and screen scope.
- Retain a remote/build-time rollback to 500 ms.

### Phase 6: Optional optimistic selection

- Restricted to reversible actions.
- Separate explicit approval and validation evidence required.

## 12. Rollback Conditions

Immediately disable the new partial/dynamic path when any condition occurs:

- duplicate business intent;
- stale route or list action;
- irreversible action from partial;
- false navigation rate above the accepted threshold;
- growing PCM or recognizer queue;
- recognizer hang or repeated timeout;
- command p95 regression above 10%;
- significant device overheating or battery regression;
- preview/final disagreement above the accepted threshold.

Rollback must restore final-only dynamic selection without disabling fixed voice
commands.

## 13. Evidence Report

Every run must produce:

```text
build fingerprint
environment and SNR
speaker/scenario ID
configuration and grammar size
raw structured logs
p50/p95/p99 table
accuracy and false-activation table
queue/CPU/memory/temperature table
failures with audio or reproducible trace reference
go/no-go decision
```

Evidence is stored under `docs/voice_recovery/evidence/` with date, device,
build and experiment name in the filename.

## 14. External Technical References

- Vosk API: https://raw.githubusercontent.com/alphacep/vosk-api/master/src/vosk_api.h
- Vosk recognizer: https://raw.githubusercontent.com/alphacep/vosk-api/master/src/recognizer.cc
- Kaldi online endpoint rules: https://kaldi-asr.org/doc/online-endpoint_8h_source.html
- Incremental word stability: https://www.isca-archive.org/interspeech_2012/mcgraw12_interspeech.html
- Android Voice Access: https://support.google.com/accessibility/android/answer/6151848?hl=en
- Apple Voice Control: https://support.apple.com/en-us/111778
