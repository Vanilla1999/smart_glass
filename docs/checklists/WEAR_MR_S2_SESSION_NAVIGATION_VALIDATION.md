# Проверка MR-S2: session, lifecycle и navigation authority

Stack base: MR-S1 (`refactor/wear-runtime-store-shell`).

## Ownership до и после

| Значение | До MR-S2 | После MR-S2 | Временный adapter |
|---|---|---|---|
| user identity | static `WearSession._user` | `WearRuntimeAuthority.session` | getters/streams `WearSession` |
| runtime active | UI/controller flags | `WearLifecycleSlice.runtimeActive` | legacy flow остаётся execution adapter |
| phone UI active | widget lifecycle flag | `WearLifecycleSlice.phoneUiActive` | UI binding переносится поэтапно |
| logical screen | `WearFlowController` | `WearNavigationSlice.logicalScreen` | legacy flow compatibility state |
| actual phone route | route-local observation | `WearNavigationSlice.actualPhoneScreen` | route adapter |
| pending navigation | controller request | versioned `WearPendingNavigation` | legacy navigation output |
| printer selection | `WearSession` | без изменений, legacy owner | удалится в MR-S4 |
| feature state | feature runtimes | без изменений | MR-S4..MR-S6 |

Production wiring verified statically:

- `WearDependencies` injects `WearSession.identityAuthority` into both
  `WearFlowController` and `WearActualScreenStore`;
- `WearFlowController` writes lifecycle/navigation only through authority
  intents and exposes legacy `WearFlowState` as a compatibility projection;
- `WearActualScreenStore.confirm()` is an epoch-bound route-observation
  adapter and owns no screen/revision fields;
- detached and widget dispose invoke `WearRuntimeAuthority.terminate()`;
- printer selection remains writable only in `WearSession` until MR-S4.

## Что проверить локально

```bash
flutter test \
  test/wear_runtime_store_test.dart \
  test/wear_runtime_store_atomicity_test.dart \
  test/wear_runtime_session_authority_test.dart \
  test/wear_runtime_navigation_authority_test.dart
```

Связанные существующие проверки:

```bash
flutter test \
  test/wear_flow_controller_test.dart \
  test/wear_flow_coordinator_integration_test.dart \
  test/flutter_wear_navigation_output_integration_test.dart
```

## Session invariants

- повторная авторизация тем же user является no-op;
- compatibility authorized event публикуется один раз;
- другой user не заменяет активную identity;
- clear session увеличивает epoch и сбрасывает revision в `0`;
- clear удаляет identity и logical navigation pending;
- printer selection остаётся отдельно legacy-owned до MR-S4;
- `WearSession.setUser/clear` ожидают authoritative receipt.

## Lifecycle invariants

- anonymous runtime нельзя активировать;
- authorization активирует runtime;
- `phoneUiActive=false` не выключает runtime;
- session clear выключает runtime, но не обязан закрывать phone UI;
- terminal очищает identity, закрывает runtime/UI admission и state stream;
- поздний intent после terminal получает typed rejection.

## Navigation invariants

- logical screen является authority;
- actual phone route может отставать;
- route observation не меняет logical screen;
- observation revision должна строго возрастать;
- acknowledgement принимается только для current request id + screen;
- новая navigation supersede старую pending request;
- duplicate pending request не создаёт новый request id;
- back использует immutable history;
- home заменяет history на один `menu`;
- session clear сбрасывает history на `main`.

## Статическая проверка

Остановить MR, если найдено хотя бы одно:

- `_user` всё ещё записывается вне aggregate authority;
- printer selection преждевременно копируется writable в aggregate;
- actual route меняет business task;
- stale observation откатывает actual route;
- stale acknowledgement очищает новый pending request;
- `paused/hidden` переводят runtime в terminal;
- повторная auth публикует второй event;
- terminal intent оставляет открытый store admission;
- `WearFlowController` создаёт собственные navigation request id/history;
- actual-screen compatibility хранит writable screen/revision;
- detached/dispose только выключает legacy controller без terminal authority;
- old store implementation остаётся импортируемым параллельно payload-aware implementation.

## Ручная проверка позже

1. Авторизоваться и выключить экран: runtime остаётся active, phone UI становится inactive.
2. Выполнить logical navigation с выключенным экраном: actual route остаётся старым.
3. Включить экран: подтвердить только latest pending navigation.
4. Быстро создать два перехода: первый acknowledgement должен быть stale.
5. Сменить пользователя: identity, pending route и history сбрасываются до перехода на auth screen.
6. После detached/terminal никакой route/auth callback не оживляет authority.

## Не запускалось агентом

Flutter, analyzer, tests, Gradle, сборка и устройство не запускались. Результат пользовательского прогона нужно записать с exact HEAD PR.
