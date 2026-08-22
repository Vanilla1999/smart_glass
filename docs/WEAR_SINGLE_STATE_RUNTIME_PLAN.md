# План перехода Wear к единому runtime state

- Статус: активный архитектурный roadmap
- Целевая ветка интеграции: `experiment/aligned-audio-frontend`
- Решение: [`decisions/ADR-0001-WEAR_SINGLE_STATE_OWNER.md`](decisions/ADR-0001-WEAR_SINGLE_STATE_OWNER.md)
- Предыдущий этап: MR #1, runtime barcode/scanner stabilization
- Acceptance предыдущего этапа: [`checklists/WEAR_RUNTIME_STABILIZATION_VALIDATION.md`](checklists/WEAR_RUNTIME_STABILIZATION_VALIDATION.md)

## 1. Цель

Сделать application runtime единственным владельцем состояния Wear-сценария, чтобы:

- телефон и очки отображали один и тот же business snapshot;
- touch, voice, hardware buttons и scanner отправляли semantic intents в одну mutation boundary;
- screen-off flow не зависел от построения Flutter widgets;
- route телефона мог отставать и затем безопасно догонять logical state;
- async-result старой операции или сессии не мог изменить актуальный state;
- разработчики не поддерживали несколько несовместимых копий focus, selection, step и status.

Целевая формула:

```text
Phone touch ---------┐
Voice ----------------┤
Hardware button ------┼--> WearIntent --> WearRuntimeStore
Barcode --------------┤                         |
Native/effect result --┘                         v
                                         WearRuntimeState
                                           /          \
                                  phone projection   glasses projection
```

## 2. Исходное состояние после stabilization MR

MR #1 исправляет runtime-first barcode routing, scanner admission/readiness, stale availability operations, printer reload reconciliation и terminal lifecycle. Это обязательная база, но состояние всё ещё распределено.

Существующие mutable holders включают:

- `WearFlowController._state`;
- `WearPrinterRuntimeState` и его stream;
- `WearScanRuntimeState` и его stream;
- `WearAvailabilityRuntimeState` и его stream;
- mutable `WearSession`;
- actual-screen store;
- локальный voice state в `WearModuleApp`;
- screen payload cache;
- status/transient timers и generations;
- screen-owned callbacks и локальные Cubit/Provider.

Проблема не в количестве классов. Проблема в количестве независимых мест, которые могут ответить на один business-вопрос.

Пример:

```text
«Какой белый принтер выбран?»

WearPrinterRuntime._whitePrinter
WearPrinterRuntime._selection
WearSession.printerSelection
WearFlowState.currentPrinterSelection
navigation extra
widget snapshot
```

Пока эти значения изменяются отдельно, один state фактически отсутствует.

## 3. Границы Variant A

План сохраняет текущий runtime-контракт:

Поддерживается:

- screen-off при живом Android process;
- живые `MainActivity` и основной Flutter engine;
- runtime в `resumed`, `inactive`, `hidden`, `paused`;
- синхронизация phone route после resume;
- foreground service и wake-lock как host/liveness mechanism.

Не поддерживается:

- восстановление после уничтожения process;
- восстановление после `force-stop`;
- headless Flutter engine;
- второй Dart isolate с отдельным store;
- автоматический restart Wear-сессии после reboot.

Следствие: aggregate state хранится в памяти живого application runtime. Persistent event journal в этот roadmap не входит.

## 4. Термины

### Authoritative state

Единственный snapshot, из которого принимаются business-решения.

### Logical screen

Текущий business step. Определяет:

- допустимые команды;
- barcode admission;
- voice grammar;
- glasses projection;
- ожидаемые effects.

### Actual phone screen

Последний подтверждённый Flutter route. Это observation, а не источник истины.

### Intent

Типизированное сообщение о намерении или результате:

```text
MoveFocus
SelectFocused
BarcodeScanned
PrinterLoadSucceeded
PhoneRouteObserved
SessionCleared
```

### Effect

Внешняя операция, которую reducer сам выполнять не должен:

```text
load printers
find barcode
print
capture photo
navigate phone
open system settings
```

### Projection

Чистое преобразование aggregate state в view model телефона или payload очков.

### Session epoch

Монотонное поколение Wear-сессии. Результат другого epoch всегда stale.

### State revision

Монотонная версия опубликованного aggregate snapshot.

### Operation ID

Идентификатор конкретного effect внутри session epoch.

## 5. Целевой aggregate state

Имена могут уточняться в кодовом MR, но semantic contract фиксируется сейчас.

```dart
class WearRuntimeState {
  const WearRuntimeState({
    required this.sessionEpoch,
    required this.revision,
    required this.session,
    required this.lifecycle,
    required this.navigation,
    required this.task,
    required this.voice,
    required this.scanner,
    required this.connectivity,
    required this.overlay,
    required this.uiEffects,
  });

  final int sessionEpoch;
  final int revision;
  final WearSessionState session;
  final WearLifecycleState lifecycle;
  final WearNavigationState navigation;
  final WearTaskState task;
  final WearVoiceState voice;
  final WearScannerState scanner;
  final WearConnectivityState connectivity;
  final WearOverlayState overlay;
  final List<WearUiEffect> uiEffects;
}
```

### 5.1 Session state

Содержит только business identity и выбранную конфигурацию сессии:

```text
authenticated user
store/employee identity
session status
printer selection после полной миграции
```

Не содержит Flutter context или native object references.

### 5.2 Lifecycle state

Разделяет:

```text
runtimeActive
phoneUiActive
terminal
foregroundHostRequested
foregroundHostObserved
```

`paused`/`hidden` выключают `phoneUiActive`, но не обязаны выключать runtime.

`detached`, logout и dispose переводят state в terminal/new epoch и закрывают admission.

### 5.3 Navigation state

```dart
class WearNavigationState {
  final WearScreenId logicalScreen;
  final WearScreenId? actualPhoneScreen;
  final WearNavigationRequest? pending;
  final List<WearNavigationEntry> history;
  final int routeObservationRevision;
}
```

Инварианты:

- команды используют `logicalScreen`;
- `actualPhoneScreen` не меняет business task;
- route acknowledgement принимается только для актуального request id;
- resume доставляет latest pending navigation, а не цепочку устаревших переходов;
- stale phone observation не откатывает logical state.

### 5.4 Task state

Нужен sealed/union state, чтобы невозможные feature-комбинации не существовали одновременно:

```text
WearTaskIdle
WearPrinterTaskState
WearScanTaskState
WearAvailabilityTaskState
WearStatusTaskState
```

Не следует создавать один плоский класс с nullable полями для всех feature.

### 5.5 Voice state

В aggregate state хранится coarse state, влияющий на UI и admission:

```text
disabled/loading/ready/reconnecting/unavailable
commandsEnabled
captureEpoch
recognition context revision
last visible error
```

Не хранятся:

- PCM chunks;
- audio buffers;
- высокочастотный level stream;
- внутренние Vosk objects.

### 5.6 Scanner state

Минимально разделяет:

```text
hardware lifecycle: released/preparing/prepared/pausing/error
barcode admission: enabled/disabled
expected logical screen
last accepted delivery id
```

`hardwarePrepared` и `barcodeAdmissionEnabled` — разные свойства.

### 5.7 Overlay/status state

Base screen, status и transient overlay должны быть versioned относительно того же `sessionEpoch` и aggregate revision.

Overlay не может незаметно менять navigation или task state.

## 6. Единственная mutation boundary

Целевой API:

```dart
abstract interface class WearRuntimeStore {
  WearRuntimeState get state;
  Stream<WearRuntimeState> get states;

  Future<void> dispatch(WearIntent intent);
}
```

Запрещено:

- публичное изменение slice напрямую;
- запись в `WearSession` из feature runtime;
- navigation callback, который одновременно мутирует feature state;
- widget callback, меняющий business model вне store;
- отдельный authoritative stream feature runtime.

### 6.1 Сериализация intents

Store обрабатывает intents последовательно.

Даже если источники конкурентны:

```text
voice select
hardware select
barcode
async print result
```

для reducer существует один порядок.

Нельзя полагаться только на Dart event loop без явного контракта очереди: nested dispatch и async effects должны иметь определённую семантику.

### 6.2 Один intent — несколько snapshots

Допустимо:

```text
idle -> loading -> success
```

Каждый опубликованный snapshot:

- атомарен;
- имеет следующую `revision`;
- не содержит частично применённую feature mutation;
- пригоден одновременно для phone и glasses projection.

## 7. Intent model

Пример иерархии:

```dart
sealed class WearIntent {
  const WearIntent();
}

sealed class WearInputIntent extends WearIntent {}
sealed class WearEffectResultIntent extends WearIntent {}
sealed class WearLifecycleIntent extends WearIntent {}
sealed class WearPhoneObservationIntent extends WearIntent {}
```

### Input intents

```text
MoveFocus(delta)
MovePage(delta)
SelectFocused
AnswerYes
AnswerNo
GoBack
GoHome
BarcodeScanned(value, deliveryId)
DynamicItemSelected(itemId)
ManualInputRequested
ClearRequested
PhotoRequested
PrintRequested
```

### Lifecycle intents

```text
SessionAuthorized
SessionCleared
PhoneUiBecameActive
PhoneUiBecameInactive
RuntimeTerminated
ForegroundHostStarted
ForegroundHostStopped
```

### Observation intents

```text
PhoneRouteObserved(screen, observationRevision)
NavigationAcknowledged(requestId, screen)
ScannerHardwareStateObserved(...)
ConnectivityObserved(...)
```

### Effect result intents

Каждый result содержит:

```text
sessionEpoch
operationId
success payload или error
```

Пример:

```dart
class PrintersLoaded extends WearEffectResultIntent {
  final int sessionEpoch;
  final int operationId;
  final List<WearPrinter> printers;
}
```

## 8. Reducer и effects

Reducer должен быть чистым относительно внешнего мира:

```text
(current state, intent) -> (next state, effects)
```

Effects исполняются adapters/handlers и возвращают result intent.

Пример:

```text
PrinterScreenEntered
  -> state.phase=loading
  -> effect LoadPrinters(epoch, operationId)

LoadPrinters effect
  -> repository call
  -> dispatch PrintersLoaded / PrintersLoadFailed
```

### Почему это обязательно

Без разделения reducer/effect:

- невозможно детерминированно проверить transition;
- stale-result guard размазывается по `try/catch`;
- navigation и repository вызовы меняют state в произвольном порядке;
- повторный tap может запустить duplicate effect.

## 9. Async safety contract

Любая операция, способная завершиться позже текущего sync turn, должна иметь identity.

### 9.1 Проверка result

Result применяется только если одновременно истинно:

```text
result.sessionEpoch == state.sessionEpoch
result.operationId == ожидаемый operationId данного slice
runtime не terminal
logical task всё ещё допускает этот result
```

### 9.2 Session reset

Logout/terminal lifecycle:

1. увеличивает `sessionEpoch`;
2. очищает ожидаемые operation ids;
3. закрывает scanner/voice input admission;
4. отменяет или игнорирует effects старого epoch;
5. публикует новый атомарный snapshot.

### 9.3 Отмена

Физическая отмена Future не всегда возможна. Контракт требует как минимум logical cancellation: поздний result игнорируется.

### 9.4 Exactly-once side effects

Для print, photo, navigation и scanner delivery нужны dedupe keys:

```text
sessionEpoch + effect kind + operationId/deliveryId
```

Повторный intent во время активной exactly-once операции либо отклоняется, либо связывается с существующей операцией.

## 10. Phone UI contract

Phone UI:

- подписывается на selector aggregate state;
- отправляет intents;
- исполняет только UI effects;
- подтверждает фактический route;
- не запускает business flow из `initState()`;
- не восстанавливает runtime state из widget state.

### 10.1 Widget lifecycle

Допустимо в `initState()`:

- создать `ScrollController`;
- подписаться на store;
- зарегистрировать UI effect handler.

Недопустимо:

- повторно `enterScreen()`;
- загружать business data только потому, что widget построился;
- сбрасывать focus/selection runtime;
- создавать второй feature state owner.

### 10.2 UI effects

Пример:

```dart
sealed class WearUiEffect {
  final int effectId;
  final int sessionEpoch;
}

class RequestManualBarcodeInput extends WearUiEffect {}
class OpenSystemWifiSettings extends WearUiEffect {}
class ShowConfirmationDialog extends WearUiEffect {}
```

UI после исполнения отправляет result intent. Result старого `effectId` не принимается.

## 11. Glasses projection contract

Целевая функция:

```dart
WearGlassesEnvelope projectGlasses(WearRuntimeState state);
```

Envelope содержит:

```text
schemaVersion
sessionEpoch
stateRevision
logicalScreen
payload
```

Требования:

- projection не мутирует store;
- одинаковый snapshot даёт одинаковый payload;
- payload старшей revision не перезаписывается младшей;
- reconnect получает latest full snapshot;
- transient overlay привязан к epoch/revision;
- phone projection и glasses projection используют один focus/item/status.

## 12. Ownership matrix

| Область | Целевой владелец | Наблюдатели/adapters | Запрещённый второй владелец |
|---|---|---|---|
| Logical screen | `WearRuntimeStore` | phone router, glasses projector, voice | Flutter route |
| Actual phone route | navigation slice | route observer | feature runtime |
| Printer selection | printer task slice | phone/glasses projection, print effect | `WearSession` mutable copy |
| Scan lookup/duplicates | scan task slice | phone/glasses projection | screen notifier |
| Availability step | availability task slice | phone/glasses projection | widget/provider |
| Voice coarse phase | voice slice | phone/glasses overlay | `WearModuleApp` authoritative local field |
| Scanner admission | scanner slice/policy | dispatcher/native adapter | actual route alone |
| Status deadline | status slice + scheduler effect | projections | widget timer |
| UI dialog/input | versioned UI effect | phone UI | runtime `BuildContext` |
| Foreground service | native host adapter | lifecycle slice observation | business store inside service |

## 13. Миграционная стратегия

Нельзя заменить всё одним MR. Нужна strangler migration с сохранением работающего flow.

### Общий compatibility contract

На промежуточных этапах:

- aggregate store существует как новый root;
- немигрированный feature может быть подключён adapter-ом;
- один screen принадлежит максимум одному business handler;
- adapter не создаёт независимую копию state;
- старый API помечается deprecated до удаления;
- каждый MR уменьшает число mutable owners.

## 14. Последовательность MR

### MR-S1. Store shell и version contract

Изменения:

- добавить `WearRuntimeState` root;
- добавить `WearRuntimeStore`;
- добавить `WearIntent` base types;
- добавить `sessionEpoch`, `revision`, operation identity;
- добавить последовательную dispatch queue;
- добавить compatibility snapshot текущего `WearFlowController` без изменения behavior;
- запретить duplicate screen ownership в composite runtime.

Почему первым:

Без root/version contract последующие features будут мигрировать в разные формы и снова потребуют объединения.

Не входит:

- перенос printer/scan/availability logic;
- изменение native scanner;
- изменение voice audio pipeline;
- изменение UI layout.

Тесты:

- новый subscriber немедленно получает current snapshot;
- revisions строго возрастают;
- intents выполняются последовательно;
- nested/parallel dispatch имеет определённый порядок;
- session reset увеличивает epoch;
- result старого epoch игнорируется;
- duplicate screen ownership отклоняется;
- compatibility snapshot не меняет существующий logical flow.

Stop/revert:

- если shell требует менять feature behavior, MR нужно разделить;
- если одновременно существуют два writable roots, MR не готов.

### MR-S2. Session, lifecycle и navigation slices

Изменения:

- перенести runtime/phone lifecycle;
- перенести logical/actual navigation;
- перенести pending request/history;
- сделать `WearSession` read-only compatibility adapter;
- route observer отправляет intents;
- terminal lifecycle создаёт новый epoch;
- scanner policy читает aggregate lifecycle/navigation state.

Почему до feature state:

Feature transitions должны сразу опираться на окончательный logical screen и session epoch.

Тесты:

- paused/hidden сохраняют runtime active;
- detached/logout завершают epoch;
- actual route может отставать;
- resume синхронизирует latest route ровно один раз;
- stale acknowledgement игнорируется;
- поздний authorization callback не оживляет terminal state;
- screen-off barcode policy использует logical screen;
- active route drift блокирует admission.

### MR-S3. Printer vertical slice

Изменения:

- перенести printer phase/list/focus/white/yellow/selection в task slice;
- `WearPrinterRuntime` превратить в reducer/effect handler;
- удалить отдельный authoritative printer stream;
- убрать mutable printer selection из `WearSession`;
- phone/glasses читают один snapshot;
- load/reload возвращают versioned result intents.

Почему printer первым:

Flow короткий, dependencies ограничены, а selection уже почти вынесен из widget tree.

Тесты:

- load без widget tree;
- white и yellow различаются;
- focus одинаков на phone/glasses;
- selection переживает phone detach/attach;
- reload сохраняет валидную пару;
- reload обрабатывает исчезновение white/yellow;
- stale load после logout игнорируется;
- два select не создают две navigation/selection операции;
- touch/voice/button приводят к одинаковому state.

### MR-S4. Scan, print и status slice

Изменения:

- перенести barcode delivery, lookup, duplicates, focus, print phase и status;
- navigation становится reducer transition + effect;
- timers заменить injectable scheduler effect;
- exactly-once print identity;
- убрать scan feature stream как authority.

Тесты:

- zero/one/many products;
- duplicate selection;
- duplicate scanner delivery consumed once;
- stale lookup/print result игнорируется;
- повторный select во время print не печатает дважды;
- status deadline через fake clock;
- timer старого epoch не навигирует;
- printer -> scan -> print без widgets;
- phone/glasses projection parity.

### MR-S5. Availability slice

Изменения:

- перенести group/product/direct/check/fill steps;
- типизировать все substeps;
- repository/photo/print/fill — effects;
- убрать отдельный availability stream;
- widgets перестают вызывать `enterScreen()`;
- duplicate/fill/status — часть одного aggregate snapshot.

Тесты:

- groups/products без widgets;
- direct scan zero/one/many;
- duplicate list parity;
- yes/no transition matrix;
- product/price-tag barcode validation;
- price-tag print exactly once;
- photo success/error/stale result;
- fill add/reset/dedupe;
- session reset во время каждого effect;
- полный availability flow при inactive phone UI.

### MR-S6. Unified input intents и UI effects

Изменения:

- touch, voice, button, barcode преобразуются в одни semantic intents;
- удалить business callbacks из `WearScreenActionHandler` для мигрированных screens;
- manual input/settings/dialogs оформить UI effects;
- effect result versioned;
- input adapters не могут менять state напрямую.

Тесты:

- touch/voice/button deep-equal final state;
- один barcode path;
- UI effect delivered once;
- stale UI result rejected;
- inactive phone откладывает или явно отклоняет UI-only effect;
- command старого screen ignored;
- очередь сохраняет порядок.

### MR-S7. Единственная projection pipeline

Изменения:

- phone selectors и glasses projector строятся из aggregate snapshot;
- transport envelope получает epoch/revision;
- убрать feature-owned glasses payload callbacks;
- reconnect отправляет latest snapshot;
- status/voice overlay versioned.

Тесты:

- golden payload каждого screen/step;
- deterministic projection;
- phone/glasses focus parity;
- revision 10 не перезаписывается revision 9;
- новый epoch принимает revision 1 и отклоняет старый epoch;
- reconnect latest snapshot;
- старый overlay не перекрывает новый screen.

### MR-S8. Удаление compatibility layer

Удалить:

- mutable static `WearSession`;
- feature authoritative streams;
- nullable runtime setters;
- screen payload cache как source of truth;
- hard-coded migrated-screen checks;
- business `enterScreen()` из widgets;
- ненужные presentation-state bridges;
- оставшиеся screen-owned business callbacks;
- duplicate actual-screen owner, если navigation slice уже принят.

Тесты/gates:

- repository search не находит запрещённые mutation paths;
- полный automated suite;
- T2151 acceptance;
- logout/detached resource release;
- screen-off printer/scan/availability scenarios;
- docs отражают фактический final state.

## 15. Test strategy

### 15.1 Reducer tests

Чистые таблицы:

```text
state + intent -> expected state + effects
```

Проверять не только happy path, но и невозможные/stale intents.

### 15.2 Store serialization tests

Проверять конкурентные inputs и nested result dispatch.

### 15.3 Effect-handler tests

Fake repositories, printer, camera, scanner, clock и navigation output.

### 15.4 Projection tests

Golden/structural tests для phone view model и glasses payload.

### 15.5 Contract tests

- capability означает реальное исполнение;
- barcode admission означает, что handler готов;
- каждый screen имеет максимум одного owner;
- UI effect имеет exactly-once acknowledgement;
- result identity проверяется единообразно.

### 15.6 Integration tests без widget tree

Критические printer/scan/availability flows должны проходить при `phoneUiActive=false`.

### 15.7 Widget tests

Проверяют только:

- selector rendering;
- intent dispatch;
- UI effect handling;
- route observation.

Не должны быть единственным доказательством business flow.

### 15.8 Hardware tests

T2151:

- 20+ barcode scans screen-off;
- 30 минут PCM;
- Firebird через 5/30 минут screen-off;
- photo capture/delete;
- printer flow;
- availability flow;
- resume route synchronization;
- logout/detached teardown.

## 16. Per-MR proof requirements

Каждый кодовый MR обязан отвечать на вопросы:

1. Какое mutable ownership удалено?
2. Какой один owner остаётся?
3. Какие intents добавлены?
4. Какие effects добавлены?
5. Как result защищён epoch/operationId?
6. Что происходит при screen change?
7. Что происходит при logout/detached?
8. Совпадают ли phone и glasses projection?
9. Какие tests доказывают invariant?
10. Как безопасно откатить MR?

Шаблон: [`checklists/WEAR_SINGLE_STATE_MR_REVIEW.md`](checklists/WEAR_SINGLE_STATE_MR_REVIEW.md).

## 17. Запреты на период миграции

Не принимать MR, который:

- добавляет новый mutable singleton;
- добавляет feature stream без плана удаления;
- читает actual route для business decision;
- запускает business load только из widget lifecycle;
- дублирует touch и voice business logic;
- использует `Object?` там, где это новый cross-layer contract;
- применяет async result без identity;
- меняет state и отправляет glasses payload двумя независимыми путями;
- переносит business logic в foreground service;
- смешивает state migration с UAC4/PCM refactoring без необходимости.

## 18. Наблюдаемость

В процессе миграции полезно логировать структурированно:

```text
sessionEpoch
stateRevision
intentType
logicalScreen
actualPhoneScreen
operationId
effectType
result accepted/rejected reason
```

Не логировать чувствительные auth payloads или персональные данные пользователя.

Для rejected stale result причина должна быть различима:

```text
wrong epoch
wrong operation id
wrong task phase
terminal runtime
superseded screen
```

## 19. Rollback strategy

Каждый vertical slice должен быть откатываемым отдельно.

Правила:

- schema aggregate root расширяется совместимо;
- adapter удаляется только после полного slice migration;
- нельзя одновременно менять repository protocol и ownership без необходимости;
- before/after behavior фиксируется contract tests;
- hardware-specific изменения отделяются от pure Dart state changes;
- при regression возвращается предыдущий adapter, а не создаётся третий state holder.

## 20. Definition of Done

Переход завершён, когда одновременно выполнено:

1. существует один authoritative `WearRuntimeState` на сессию;
2. только `dispatch(WearIntent)` меняет business-state;
3. каждый snapshot имеет epoch/revision;
4. каждый async result имеет epoch/operation identity;
5. logical screen управляет commands, scanner и glasses;
6. actual phone route является observation;
7. phone и glasses строятся из одного snapshot;
8. feature runtimes не владеют отдельными authoritative streams;
9. widgets не запускают business flow из lifecycle;
10. UI-only действия оформлены effects;
11. foreground service не владеет Dart state;
12. logout/detached окончательно закрывают resources/admission;
13. printer/scan/availability проходят без widget tree;
14. automated и hardware gates зелёные;
15. legacy owners и compatibility adapters удалены;
16. canonical docs соответствуют коду.

## 21. Ближайшее действие

После принятия этого документа следующий кодовый MR — **MR-S1: Store shell и version contract**.

Он должен быть намеренно небольшим: root state, intent base, serialization, epoch/revision и compatibility adapter без переноса feature behavior. Это создаст стабильную форму, в которую последовательно мигрируют lifecycle/navigation, printers, scan и availability.
