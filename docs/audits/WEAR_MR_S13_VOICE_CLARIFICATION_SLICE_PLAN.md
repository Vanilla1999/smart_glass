# MR-S13: Aggregate voice-clarification presentation slice

Дата: 2026-08-24.

## Причина

Voice clarification affects business behavior: visible candidates define grammar and selection, focus is shared with glasses, stale source revisions must be rejected, and home/cancel may preserve or clear the clarification context. Therefore `WearFlowState.currentVoiceClarificationArgs`, focus and notice cannot remain a controller-owned UI cache.

## Цель

- move clarification args, focus and notice into aggregate presentation state;
- add typed epoch/screen-bound open/notice/clear intents;
- make phone/glasses grammar and selection project the committed aggregate snapshot;
- preserve clarification only for the intentional `voiceClarification <-> homeConfirm` round trip;
- clear it on unrelated navigation, session reset and terminal teardown;
- remove controller-owned clarification fields and payload builder;
- keep PCM/Vosk/audio objects outside aggregate state.

## Tests/gates

- open from the current source screen;
- stale source/epoch rejection;
- focus and paging parity;
- list-revision validation before selection;
- home-confirm round-trip preservation;
- unrelated navigation/session reset clear;
- phone/glasses projection parity;
- repository search finds no controller-owned clarification fields.

No Flutter/analyzer/Gradle/build/device commands are run.
