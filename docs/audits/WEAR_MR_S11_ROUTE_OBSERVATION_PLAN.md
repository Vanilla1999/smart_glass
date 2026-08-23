# MR-S11: Aggregate logical screen and route-observation boundary

Дата: 2026-08-24.

## 1. Контекст

- Integration branch: `experiment/aligned-audio-frontend`.
- Base commit: `7f9e0deafc4633c51ee4b77f70794044fe44e4cc`.
- Work branch: `refactor/wear-runtime-route-observation`.
- Предыдущий этап: PR #15 / MR-S10 — aggregate-owned focus четырёх phone screens.
- Нормативные документы:
  - `docs/WEAR_SINGLE_STATE_RUNTIME_PLAN.md`;
  - `docs/decisions/ADR-0001-WEAR_SINGLE_STATE_OWNER.md`;
  - `docs/decisions/ADR-0002-WEAR_STORE_EXECUTION_ORDER.md`.

После MR-S10 presentation focus выбранных экранов уже принадлежит aggregate
runtime. Однако orchestration boundary всё ещё читает logical screen из
`WearFlowController.state`:

- `WearModuleApp` подписан на `WearFlowController.stateStream`;
- scanner/voice reconfiguration сравнивает route с `flow.state.screen`;
- `WearBarcodeDispatcher` захватывает source screen из controller state;
- `WearVoiceControlService` получает screen через controller;
- router listener сначала отправляет `PhoneRouteObserved`, а затем повторно
  вызывает `flow.observeRoute()`, который меняет compatibility state и может
  запускать screen lifecycle;
- несколько widgets вызывают `enterScreen()` из `initState()` и тем самым делают
  построение UI участником business lifecycle.

Это нарушает принятое разделение:

```text
logicalScreen       = business authority
actualPhoneScreen   = observation Flutter route
widget attachment   = observation/rendering only
```

## 2. Цель

Сделать `WearRuntimeAuthority.payload.navigation.logicalScreen` единственным
production source текущего business screen для:

- scanner admission и barcode delivery;
- voice grammar/configuration;
- hardware/voice command attribution;
- route drift comparison;
- debug state rendering;
- screen-action refresh admission.

Flutter router должен только отправлять epoch-bound `PhoneRouteObserved` и
acknowledgement актуального pending navigation. Он не должен повторно выполнять
business entry.

## 3. Ownership ledger

| Value/decision | Owner до MR | Owner после MR | Retained compatibility |
|---|---|---|---|
| Logical business screen | Aggregate, но часть orchestration читает `WearFlowState.screen` | Только aggregate navigation slice | `WearFlowState.screen` остаётся derived view до MR-S12 |
| Actual phone route | Router + aggregate observation, затем controller `observeRoute()` | Aggregate `actualPhoneScreen` observation | Router/local `_actualRouteScreen` только host cache |
| Barcode source screen | `WearFlowController.state.screen` | Captured aggregate logical screen + captured epoch | Нет writable mirror |
| Voice screen provider | Controller state | Aggregate logical screen | Нет |
| Widget business entry | `enterScreen()` из `initState()` на legacy screens | Только prior typed navigation intent/reducer transition | Screen action registration остаётся UI wiring |
| Glasses screen payload | Aggregate projection плюс legacy widget publish calls | Aggregate projection only | Transient UI-only overlay остаётся до MR-S12 |

## 4. Scope реализации

### 4.1. `WearModuleApp`

1. Удалить импорт и subscription на `WearFlowState`.
2. Использовать `WearRuntimeAuthority.states` как replayable source lifecycle,
   controls и logical screen.
3. При изменении aggregate logical screen:
   - синхронизировать scanner policy;
   - перенастроить voice grammar;
   - не зависеть от построения нового widget.
4. Сравнивать screen-action refresh с aggregate logical screen.
5. В scanner orchestration читать logical screen только из aggregate snapshot.
6. В router listener:
   - отправлять только epoch-bound route observation;
   - подтверждать только совпадающий aggregate pending request;
   - не вызывать `WearFlowController.observeRoute()`;
   - не менять feature state из route attachment.
7. Debug overlay строить из `WearRuntimeState`, а не controller stream.

### 4.2. Barcode boundary

1. `WearBarcodeDispatcher` должен зависеть от `WearRuntimeAuthority`, а не от
   controller business state.
2. На `onScanEvent` атомарно захватывать:
   - `sessionEpoch`;
   - aggregate `logicalScreen`;
   - epoch-bound control adapter.
3. Delivery receipt и semantic barcode intent должны использовать один captured
   epoch/screen.
4. Поздний queued barcode старого epoch или screen должен быть rejected, а не
   переименован в текущий input.

### 4.3. Voice screen provider

`WearVoiceControlService.screenProvider` читает только
`authority.payload.navigation.logicalScreen`.

### 4.4. Widget lifecycle

Удалить business `enterScreen()` из production widgets. Для screens, где он ещё
присутствует:

- menu;
- home-confirm;
- continue-scan;
- availability-interaction;
- help;
- status;
- settings;
- voice-clarification;
- любые другие найденные presentation paths.

Widget может:

- подписаться на aggregate projection;
- зарегистрировать UI action handler;
- создать controller/scroll resources;
- выполнить UI-only effect.

Widget не может:

- менять logical screen;
- повторно запускать feature entry/load;
- сбрасывать business focus;
- публиковать canonical glasses payload.

Удалить legacy `publishScreenPayload()` из help/status там, где canonical payload
уже строится `WearRuntimeProjection.projectGlasses()`.

### 4.5. Controller compatibility boundary

В пределах этого MR не удаляется весь `WearFlowController`, но production
screen-source helpers должны читать aggregate navigation. Retained compatibility
state не может участвовать в barcode/voice/scanner decisions.

Физическое удаление `WearFlowState`, status/transient compatibility state и
временного MR-S10 facade — MR-S12.

## 5. Тесты/specifications

Добавить source/contract tests, которые доказывают:

1. `WearModuleApp` не импортирует `wear_flow_state.dart` и не подписывается на
   `flow.stateStream`.
2. `WearModuleApp` не читает `flow.state.screen` для scanner/voice/route decisions.
3. Router callback не вызывает `flow.observeRoute()`.
4. Barcode dispatcher не зависит от `WearFlowController` и явно передаёт captured
   epoch в semantic dispatch.
5. Voice screen provider использует aggregate navigation.
6. Ни один production Dart-файл под `lib/modules/wear/presentation` не вызывает
   `.enterScreen(`.
7. Help/status widgets не публикуют canonical glasses payload вручную.
8. Actual route observation не меняет logical screen.
9. Старый barcode adapter/epoch не может применить delivery к новой сессии.
10. Screen-off logical transition инициирует scanner/voice synchronization без
    построения widget tree.

## 6. Не входит

- удаление всего `WearFlowController`;
- перенос voice-clarification arguments/focus/notice в aggregate slice;
- удаление legacy `WearFlowState` fields;
- перенос UI-only dialog/draft state;
- изменение UAC4, PCM, Vosk или native scanner protocol;
- изменение repository/API contracts;
- Flutter/Gradle/build execution;
- hardware validation.

## 7. Review checklist

- Logical screen берётся из одного committed snapshot.
- Barcode screen и epoch захвачены одной admission boundary.
- Route observation не вызывает business entry.
- Pending navigation acknowledgement проверяет request id, target screen и
  captured epoch.
- Widget rebuild/deep-link не запускает load/print/photo повторно.
- Удаление `enterScreen()` не лишает feature reducer typed entry intent: logical
  transition уже происходит до phone navigation effect.
- Scanner policy использует aggregate controls и logical screen.
- Voice grammar обновляется при aggregate transition даже при inactive phone UI.
- Debug/UI caches не становятся business owners.
- Diff не касается audio/native/build artifacts.

## 8. Validation limitation

По явному ограничению владельца не запускаются:

- `flutter test`;
- `flutter analyze` / `dart analyze`;
- Gradle;
- APK/build;
- emulator/device tests.

Validation состоит из полного GitHub diff review, проверки call graph и
source-level regression specifications. Исполняемая проверка остаётся owner-run
release gate.

## 9. Порядок

1. Plan-first commit.
2. Aggregate route/scanner/voice implementation.
3. Widget lifecycle cleanup.
4. Tests/specifications и validation record.
5. PR в integration branch.
6. Static review exact HEAD.
7. Review-fix commits.
8. Повторный review.
9. Merge.
10. Удаление work branch доступным GitHub ref API; посторонние refs не трогать.

## 10. Stop/revert

MR разделяется, если удаление одного widget `enterScreen()` требует перенести
отдельную business state machine. В таком случае widget остаётся вне merge до
следующего bounded ownership MR; нельзя временно вводить route-to-business dual
write.

Rollback возвращает только route/lifecycle adapter wiring. Он не создаёт второй
store и не меняет native protocol.
