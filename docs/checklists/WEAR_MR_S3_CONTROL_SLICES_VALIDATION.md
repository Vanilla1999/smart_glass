# Проверка MR-S3: voice, scanner и connectivity control slices

Stack base: MR-S2 (`refactor/wear-runtime-session-navigation`).

## Ownership transfer

| Значение | До | После | Не переносится |
|---|---|---|---|
| coarse voice phase/admission | `WearModuleApp`/voice session flags | `WearVoiceControlSlice` | PCM, audio level, Vosk objects |
| scanner hardware lifecycle | UI orchestration/policy flags | `WearScannerControlSlice.hardwarePhase` | vendor scanner instance/lease |
| barcode admission | route/UI-derived bool | `WearScannerControlSlice.barcodeAdmissionEnabled` | barcode business handling |
| connectivity coarse status | reporter/service local state | `WearConnectivityControlSlice` | sockets/clients |

## Локальные тесты

```bash
flutter test \
  test/wear_runtime_control_slices_test.dart \
  test/wear_runtime_control_adapter_test.dart \
  test/wear_runtime_session_authority_test.dart \
  test/wear_scanner_runtime_policy_test.dart
```

Production wiring reviewed statically:

- `WearModuleApp` reports coarse voice state/admission through an epoch-bound
  `WearRuntimeControlAdapter`; command dispatch reads aggregate admission;
- scanner hardware operations report preparing/prepared/pausing/released/error
  observations through the adapter, then aggregate policy evaluates admission;
- `WearBarcodeDispatcher` reads aggregate admission and dispatches an
  epoch-bound delivery intent before invoking the legacy MR-S5 business handler;
- Wi-Fi polling remains an I/O/projection concern of `WearStatusIconReporter`,
  which reports coarse online/offline observations without owning aggregate state;
- session clear/authorization replaces adapter callbacks with callbacks that
  explicitly capture the current authority epoch;
- printer, scan, availability, PCM, Vosk and audio lease ownership is unchanged.

## Voice

- observation содержит current `sessionEpoch` и monotonic revision;
- capture epoch не может откатиться;
- commands enabled только в `ready`;
- stale observation не публикует snapshot;
- PCM/audio buffers/audio level не являются полями aggregate state;
- terminal/session clear выключает command admission.

## Scanner

- hardware phase и barcode admission независимы;
- authorized runtime может требовать prepared hardware на non-barcode screen;
- active phone UI требует actual/logical route match;
- background использует logical screen;
- stale logical screen не включает admission;
- delivery id принимается один раз;
- session clear atomарно переводит scanner в released/admission=false;
- terminal selector безусловно возвращает false/false.

## Connectivity

- observation revision строго возрастает;
- stale observation не откатывает online/offline state;
- connectivity не решает navigation или feature step;
- terminal может сохранить диагностическое connectivity observation, но не admission.

## Статическое ревью

Блокировать MR, если:

- control state создан отдельным store;
- `WearModuleApp` остаётся новым writable owner после подключения adapter;
- scanner admission зависит только от actual route;
- hardware pause следует из любого non-barcode screen;
- session clear сохраняет prepared/admission старого epoch;
- success/error observation имеют разные stale guards;
- PCM chunk или audio-level event увеличивает aggregate revision;
- delivery receipt подтверждается только фактом callback, а не state admission.

## Ручная проверка позже

1. Авторизоваться: hardware desired=true, admission зависит от screen.
2. На active UI с route drift barcode закрыт.
3. Выключить экран: при logical scan screen admission открывается.
4. Перейти на photo/non-barcode step: hardware остаётся подготовленным, admission закрыт.
5. Logout: voice disabled, scanner released, admission закрыт одним epoch snapshot.
6. Поздний native callback старого epoch отклоняется.

## Не запускалось агентом

Flutter, analyzer, tests, Gradle, build и устройство не запускались.
