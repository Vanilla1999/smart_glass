# MR-S12: Demote WearFlowController to projection/orchestration only

Дата: 2026-08-24.

## Контекст

- Integration branch: `experiment/aligned-audio-frontend`.
- MR-S10 сделал aggregate owner focus простых phone screens.
- MR-S11 отделил lifecycle этих screens и scanner/voice source от compatibility screen.
- `WearFlowController` всё ещё содержит legacy `WearFlowState`, callbacks, timers и route extras. Наличие класса допустимо только если ни одно business decision и ни одна mutation не используют его как authoritative owner.

## Цель

1. Все screen/admission/command/navigation decisions читают `WearRuntimeState`.
2. Все business mutations проходят через typed aggregate dispatch/effects.
3. `enterScreen()` перестаёт запускать или менять business flow; compatibility call становится observation/render-only и затем удаляется из production widgets.
4. `observeRoute()` не запускает feature business entry.
5. Background feature entry происходит от aggregate logical transition/runtime lifecycle, а не widget attachment.
6. Legacy `WearFlowState` остаётся только derived compatibility projection для ещё не удалённых UI wiring consumers; записывать из него business values нельзя.
7. Controller-owned focus echo и screen-based business decisions удаляются.

## Не входит

- UAC4/PCM/Vosk transport;
- native scanner protocol;
- repositories/printer protocol;
- UI layout;
- persistent process-death restoration.

## Проверки

- repository gate запрещает `_state.screen` как source в input/command/admission paths;
- `enterScreen`/`observeRoute` не вызывают background business entry;
- logical navigation transition вызывает feature entry ровно из aggregate path;
- widget `initState` не является обязательным для printer/scan/availability flow;
- compatibility state cannot dispatch a different aggregate focus/navigation value;
- stale epoch/screen results stay rejected;
- Flutter/analyzer/Gradle/builds are not run.

## Workflow

Plan commit → implementation → PR → static review → fixes → second review → merge → cleanup.
