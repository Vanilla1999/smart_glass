# T2151 False Partial Command Handoff

## Purpose

Analyze false navigation caused by a transient Vosk command partial and choose
the smallest safe execution policy. This note separates facts present in the
device log from the operator's report.

## Evidence

Full raw device log:

`docs/voice_recovery/evidence/t2151_voice_recognition_2026-07-29.log`

Relevant ranges:

- Lines 213-231: VAD starts, Vosk emits `доступность`, the 150 ms stable-partial
  timer emits `openAvailability`, and navigation completes.
- Lines 241-256: the next captured utterance is recognized as `вверх` after the
  application has already changed screens.
- Lines 327-346: a second `доступность` stable partial causes another
  `openAvailability` navigation.

First false-navigation sequence from the log:

```text
22:57:14.972 VAD_START segmentId=10
22:57:15.271 partial text="доступность" command=openAvailability
22:57:15.424 stable_partial emits openAvailability
22:57:15.425 navigation to /wear_availability_interaction
22:57:15.984 VAD_ENDPOINT segmentId=10
```

Operator report: `вверх` was spoken when the unexpected availability transition
occurred. The text log proves that Vosk emitted the transient command and that
the application executed it before endpoint. It does not contain ground-truth
audio transcription, so the spoken phrase itself remains operator-reported.

The previously referenced temporary file
`/tmp/opencode/t2151_post_sequence.log` is no longer present. Use the committed
raw evidence above for reproducible analysis.

## Current Behavior

The menu catalog currently configures:

```text
вверх           immediateExactPartial
вниз            immediateExactPartial
доступность     stableExactPartial
справка         stableExactPartial
настройки       stableExactPartial
печать ценников endpointOnly
```

Code locations:

- `lib/modules/wear/domain/service/voice_command/voice_action_catalog.dart:248`
- `lib/modules/wear/domain/service/voice_command/recognition_arbiter.dart:69`
- `lib/modules/wear/domain/service/voice_command/wear_voice_control_service.dart:79`

For `stableExactPartial`, the application executes a command after the same
partial remains unchanged for 150 ms. It does not wait for a Vosk endpoint.

## Problem

A constrained recognizer can temporarily map incomplete, noisy, or
out-of-grammar audio to one of the allowed phrases. A partial is a provisional
hypothesis and may change as more PCM arrives. `[unk]` reduces this behavior but
does not guarantee rejection.

The application currently treats a 150 ms stable partial as sufficient proof
for navigation. Therefore a provisional `доступность` can change the route
before Vosk has finalized the utterance.

This is not caused by selecting an item using part of its displayed name.
`VoiceListMatcher` operates after speech has been transcribed and is a separate
feature. The observed failure occurs earlier, in command ASR and partial command
arbitration.

Exact text matching in `VoiceActionCatalog` also cannot prevent this case. It
rejects unknown text, but if Vosk has already converted unknown or incomplete
audio into the exact text `доступность`, the catalog has no access to the
original spoken phrase.

## Minimal Solution Without Double Recognition

Keep one screen-scoped constrained recognizer and the existing registered
command grammar. Change commands that navigate or mutate state from
`stableExactPartial` to `endpointOnly`.

Recommended policy:

```text
up/down and other reversible focus movement -> immediateExactPartial
navigation and state changes               -> endpointOnly
destructive actions                         -> endpointOnly plus confirmation
```

For the menu this means at least:

```text
доступность -> endpointOnly
справка     -> endpointOnly
настройки   -> endpointOnly
назад       -> endpointOnly
```

This directly prevents the logged failure mode because `openAvailability` can
no longer execute from a transient partial. It adds endpoint latency but does
not replay audio and does not add a second recognizer.

## Limitation of the Minimal Solution

An endpoint result can still be a false positive. One constrained recognizer
cannot guarantee that out-of-grammar speech will become `[unk]`; it may finalize
the nearest permitted command. The minimal solution protects against premature
partial execution, not every possible false command.

If endpoint-only behavior still produces unacceptable false activations on the
T2151 negative corpus, then add a second-stage verifier using the retained
utterance PCM. Do not add that complexity before measuring endpoint-only false
activation rate.

## Questions for Review

1. Is endpoint-only execution for all route and state-changing commands the
   correct first fix?
2. Are there any commands besides `up` and `down` whose partial execution is
   both necessary and safely reversible?
3. What endpoint latency is acceptable on T2151?
4. What negative corpus and false-activation target should gate release?
5. Should a second unconstrained replay be added only if endpoint-only testing
   fails the target?

## Verification Required

Run on physical T2151 with raw command logs enabled:

```text
Known commands: each command repeated at least 20 times
Confusable speech: вверх/вниз plus words resembling menu commands
Unknown speech: normal sentences not present in grammar
Environment: silence, store noise, nearby speaker, device movement
```

Primary metric:

```text
false activation rate = unintended executed commands / negative utterances
```

Acceptance must verify that no route-changing command is emitted with
`source=stable_partial` and that known endpoint-only commands still execute once
per utterance.
