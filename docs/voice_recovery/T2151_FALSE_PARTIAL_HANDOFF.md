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

## Patched Policy

Production command activation is now restricted to:

```text
вверх/вниз                   immediateExactPartial
all other production actions endpointOnly
```

No production `VoiceActionEntry` uses `stableExactPartial`. Catalog validation
has an explicit closed allowlist containing only `up` and `down`; any other
partial activation policy fails with `ArgumentError` in tests and debug runs.
Ignored endpoint-only partials remain visible once per utterance/text in the
diagnostic log:

```text
[VOICE_POLICY] ... kind=partial ... policy=endpointOnly decision=ignored_until_endpoint
```

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

## Implemented Minimal Solution

Keep one screen-scoped constrained recognizer and the existing registered
command grammar. Change commands that navigate or mutate state from
`stableExactPartial` to `endpointOnly`.

Implemented policy:

```text
up/down                      -> immediateExactPartial
all other production actions -> endpointOnly
```

This directly prevents the logged failure mode because `openAvailability` can
no longer execute from a transient partial. It adds endpoint latency but does
not replay audio and does not add a second recognizer.

## Limitation of the Minimal Solution

An endpoint result can still be a false positive. The T2151 hardware log already
contains a false `streamFinal` value of `выбрать` that executed `select`. One constrained recognizer
cannot guarantee that out-of-grammar speech will become `[unk]`; it may finalize
the nearest permitted command. The minimal solution protects against premature
partial execution, not every possible false command.

Second-stage acoustic verification, phrase hardening, and speaker gating are
outside this patch. Measure the endpoint-only false activation rate before
choosing a follow-up.

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
per utterance. Hardware status remains `DEVICE_PENDING` until this patched build
is rerun on a physical T2151. False endpoint commands must be counted separately.
