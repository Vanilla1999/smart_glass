# План перехода Wear к единому runtime state

- Статус: активный архитектурный roadmap
- Целевая ветка интеграции: `experiment/aligned-audio-frontend`
- Ownership-решение: [`decisions/ADR-0001-WEAR_SINGLE_STATE_OWNER.md`](decisions/ADR-0001-WEAR_SINGLE_STATE_OWNER.md)
- Execution-решение: [`decisions/ADR-0002-WEAR_STORE_EXECUTION_ORDER.md`](decisions/ADR-0002-WEAR_STORE_EXECUTION_ORDER.md)
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
- scanner lifecycle/admission state в UI orchestration;
- connectivity/status reporters;
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

План сохраняет текущий runtime-контракт.

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

Snapshot, из которого принимаются business-решения и который имеет единственного writable owner.

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

### Dispatch receipt

Типизированный результат обработки intent. Он сообщает, был ли intent принят текущим logical state, но не подменяет поздний business-result внешнего effect.

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

Чистое преобразование aggregate snapshot в view model телефона или payload очков.

### Session epoch

Поколение Wear-сессии в пределах жизни store/process. Результат другого epoch всегда stale.

### State revision

Монотонная версия опубликованного aggregate snapshot внутри одного epoch.

### Operation ID

Идентификатор конкретного async effect внутри `sessionEpoch`.

## 5. Переходный ownership contract

Целевой store нельзя внедрять как второй writable root рядом с существующими runtimes.

Для каждого business value на каждом этапе существует ровно один writable owner:

```text
legacy owner -> ownership transfer MR -> aggregate slice
```

Пока slice не мигрирован:

- legacy component остаётся единственным writable owner;
- aggregate shell может публиковать только read-only adapted view;
- adapter не хранит самостоятельную mutable копию;
- запись через aggregate mirror запрещена;
- tests сравнивают mirror с текущим owner, но не синхронизируют два stores.

В MR передачи ownership:

1. aggregate slice становится единственным writable owner;
2. legacy API превращается в read-only/deprecated facade либо удаляется;
3. dual write запрещён даже как «временная страховка»;
4. feature stream больше не считается authoritative;
5. phone/glasses начинают читать migrated slice;
6. rollback возвращает предыдущий owner, но не создаёт третий.

### Ownership ledger

Каждый migration MR содержит таблицу:

| Business value | Owner до MR | Owner после MR | Read-only compatibility view | Этап удаления |
|---|---|---|---|---|
| | | | | |

Если таблицу нельзя заполнить однозначно, MR не готов.

## 6. Целевой aggregate state

Имена могут уточняться в кодовом MR, но semantic contract фиксируется сейчас.

```dart
@immutable
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
    required this.pendingUiEffects,
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
  final WearUiEffectQueue pendingUiEffects;
}
```

State и все вложенные collections immutable/unmodifiable. Equality и selectors не должны зависеть от identity mutable list/map.

### 6.1 Version semantics

Transport и stale ordering сравниваются по tuple:

```text
(sessionEpoch, revision)
```

Правила:

- `sessionEpoch` увеличивается при новой авторизованной сессии, logout/reset и terminal teardown по единой implementation policy;
- внутри epoch `revision` только возрастает;
- новый epoch может начать revision заново;
- snapshot старого epoch всегда stale независимо от большого revision;
- no-op intent не публикует snapshot и не увеличивает revision;
- регистрация pending operation/effect является изменением state и увеличивает revision;
- projection/read не увеличивает revision;
- process restart создаёт новый lifetime; cross-process ordering Variant A не поддерживает.

### 6.2 Session state

Содержит только business identity и уже мигрированную конфигурацию сессии:

```text
authenticated user
store/employee identity
session status
printer selection после MR-S4
```

Не содержит Flutter context или native object references.

### 6.3 Lifecycle state

Разделяет:

```text
runtimeActive
phoneUiActive
terminal
foregroundHostRequested
foregroundHostObserved
```

`paused`/`hidden` выключают `phoneUiActive`, но не обязаны выключать runtime.

`detached`, logout и dispose закрывают input admission и supersede operations старого epoch.

### 6.4 Navigation state

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
- stale phone observation не откатывает logical state;
- route observer не вызывает feature load напрямую.

### 6.5 Task state

Нужен sealed/union state, чтобы невозможные feature-комбинации не существовали одновременно:

```text
WearTaskIdle
WearPrinterTaskState
WearScanTaskState
WearAvailabilityTaskState
```

Status/transient presentation хранится в overlay/status slice и не дублируется как второй task owner.

Не следует создавать один плоский класс с nullable полями для всех feature.

### 6.6 Voice state

В aggregate state хранится только coarse state, влияющий на UI и admission:

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
- внутренние Vosk objects;
- native audio lease object.

### 6.7 Scanner state

Минимально разделяет:

```text
hardware lifecycle: released/preparing/prepared/pausing/error
barcode admission: enabled/disabled
expected logical screen
last accepted delivery id
```

`hardwarePrepared` и `barcodeAdmissionEnabled` — разные свойства.

### 6.8 Connectivity state

Содержит только coarse observations, необходимые business/UI:

```text
unknown/online/offline/degraded
last observation revision
displayable error
```

Сам network/socket/client объект в state не хранится. Polling и native observation являются effects/adapters.

### 6.9 Overlay/status state

Base status и transient overlay versioned относительно того же `sessionEpoch` и aggregate revision.

Overlay:

- не меняет task/navigation скрытым callback;
- имеет deadline/generation либо scheduler effect identity;
- не может восстановить payload старого logical screen;
- не дублирует business status в widget-local timer.

### 6.10 Pending UI effects

Это bounded pending state, не append-only event log.

```text
effectId
sessionEpoch
effect kind
payload
created revision
delivery/ack status
```

Правила:

- один semantic request не создаёт два pending effects;
- UI reconnect/rebuild видит тот же effect ID;
- acknowledgement удаляет effect атомарно;
- supersede/cancel имеет typed intent;
- reset удаляет effects старого epoch;
- очередь имеет явный maximum или one-per-kind policy;
- delivery count не используется как business result.

## 7. Единственная mutation boundary

Целевой API:

```dart
abstract interface class WearRuntimeStore {
  WearRuntimeState get state;
  Stream<WearRuntimeState> get states;

  Future<WearDispatchResult> dispatch(WearIntent intent);
  Future<void> dispose();
}
```

`states`, commit/effect/receipt ordering, concurrency effects и terminal semantics `dispose()` определены в ADR-0002 и не могут быть выбраны заново каждым feature MR.

Пример receipt:

```dart
class WearDispatchResult {
  const WearDispatchResult({
    required this.accepted,
    required this.sessionEpoch,
    required this.revision,
    this.reason,
  });

  final bool accepted;
  final int sessionEpoch;
  final int revision;
  final WearDispatchRejectReason? reason;
}
```

Семантика:

- Future завершается после commit/scheduling boundary данного intent, а не после всех внешних effects;
- `accepted=true` означает, что intent принадлежал текущему state и был обработан/запустил operation;
- `accepted=false` имеет typed reason: stale screen, terminal, unsupported, duplicate, busy, stale epoch и т.п.;
- receipt revision — snapshot после обработки intent либо неизменившаяся revision для rejected no-op;
- scanner/native adapter использует receipt для acknowledgement delivery;
- поздний business success/error приходит отдельным result intent;
- receipt не является вторым state и не хранится как mutable source.

Запрещено:

- публичное изменение slice напрямую;
- запись в `WearSession` из feature runtime после ownership transfer;
- navigation callback, который одновременно мутирует feature state;
- widget callback, меняющий business model вне объявленного owner;
- отдельный authoritative stream feature runtime;
- mirror, который можно изменять независимо от legacy owner.

### 7.1 Сериализация intents

Store обрабатывает intents последовательно.

Даже если источники конкурентны:

```text
voice select
hardware select
barcode
async print result
```

для reducer существует один порядок.

Nested dispatch не выполняет reducer re-entrantly: intent ставится в хвост той же очереди. Error одного intent не оставляет очередь навсегда в processing state.

### 7.2 Commit, effects и receipt

Нормативный порядок:

```text
validate/reduce
-> commit immutable snapshot и expected operation identity
-> publish snapshot
-> schedule/register effects
-> complete dispatch receipt
-> effects later dispatch success/error intents
```

Медленный внешний effect не удерживает dispatch queue. Out-of-order completion допускается только при `sessionEpoch + operationId` guards. Exclusive resources получают отдельную mutex/dedupe policy.

### 7.3 Один intent — несколько snapshots

Допустимо:

```text
idle -> loading -> success
```

Каждый опубликованный snapshot:

- атомарен;
- имеет следующую `revision`;
- не содержит частично применённую feature mutation;
- пригоден одновременно для phone и glasses projection.

No-op/отклонённый stale intent не увеличивает revision.

## 8. Intent model

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
VoiceStateObserved(...)
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

## 9. Reducer и effects

Reducer должен быть чистым относительно внешнего мира:

```text
(current state, intent) -> (next state, effects, receipt)
```

Effects исполняются adapters/handlers и возвращают result intent.

Пример:

```text
PrinterScreenEntered
  -> state.phase=loading
  -> state.expectedLoadOperationId=N
  -> effect LoadPrinters(epoch, N)
  -> accepted receipt

LoadPrinters effect
  -> repository call
  -> dispatch PrintersLoaded / PrintersLoadFailed
```

### Почему это обязательно

Без разделения reducer/effect:

- невозможно детерминированно проверить transition;
- stale-result guard размазывается по `try/catch`;
- navigation и repository вызовы меняют state в произвольном порядке;
- повторный tap может запустить duplicate effect;
- success и error часто получают разные guards;
- adapter не может честно подтвердить принятие input.

## 10. Async safety contract

Любая операция, способная завершиться позже текущего sync turn, должна иметь identity.

### 10.1 Проверка result

Result применяется только если одновременно истинно:

```text
result.sessionEpoch == state.sessionEpoch
result.operationId == expected operationId данного slice
runtime не terminal
logical task всё ещё допускает этот result
```

Success и error проходят одну и ту же функцию admission. Нельзя защищать success и забывать catch path.

### 10.2 Session reset

Logout/terminal lifecycle:

1. supersede текущий epoch;
2. очищает ожидаемые operation IDs;
3. закрывает scanner/voice input admission;
4. отменяет или логически игнорирует effects старого epoch;
5. удаляет pending UI effects старого epoch;
6. публикует новый атомарный snapshot.

Точный момент увеличения epoch фиксируется в MR-S1 tests; правило должно быть единым для auth, logout и terminal paths.

### 10.3 Отмена

Физическая отмена Future не всегда возможна. Контракт требует как минимум logical cancellation: поздний result игнорируется и логируется с причиной.

### 10.4 Exactly-once side effects

Для print, photo, navigation и scanner delivery нужны dedupe keys:

```text
sessionEpoch + effect kind + operationId/deliveryId
```

Повторный intent во время активной exactly-once операции либо отклоняется typed receipt, либо связывается с существующей операцией. Решение для каждого effect фиксируется тестом.

## 11. Phone UI contract

Phone UI:

- подписывается на selector aggregate state;
- отправляет intents;
- исполняет только UI effects;
- подтверждает фактический route;
- не запускает business flow из `initState()`;
- не восстанавливает runtime state из widget state.

### 11.1 Widget lifecycle

Допустимо в `initState()`:

- создать `ScrollController`;
- подписаться на store;
- зарегистрировать UI effect handler.

Недопустимо:

- повторно `enterScreen()`;
- загружать business data только потому, что widget построился;
- сбрасывать focus/selection runtime;
- создавать второй feature state owner.

### 11.2 UI effects

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

UI после исполнения отправляет typed acknowledgement/result intent. Result старого `effectId` не принимается.

При `phoneUiActive=false` effect policy задаётся явно:

- defer до resume;
- выполнить voice/glasses alternative;
- reject с отображаемым status.

Молчаливый вызов `BuildContext` в фоне запрещён.

## 12. Glasses projection contract

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
- payload меньшей tuple `(epoch, revision)` не перезаписывает больший;
- reconnect получает latest full snapshot;
- transient overlay привязан к epoch/revision;
- phone projection и glasses projection используют один focus/item/status.

До финального MR-S8 aggregate shell может использовать read-only legacy projection adapters. Они не являются state owners и удаляются по мере migration slices.

## 13. Ownership matrix

| Область | Целевой владелец | Наблюдатели/adapters | Запрещённый второй владелец |
|---|---|---|---|
| Logical screen | `WearRuntimeStore` | phone router, glasses projector, voice | Flutter route |
| Actual phone route | navigation slice | route observer | feature runtime |
| Session identity | session slice | auth UI, effects | mutable `WearSession` copy |
| Printer selection | printer task slice | phone/glasses projection, print effect | mutable `WearSession` copy |
| Scan lookup/duplicates | scan task slice | phone/glasses projection | screen notifier |
| Availability step | availability task slice | phone/glasses projection | widget/provider |
| Voice coarse phase | voice slice | phone/glasses overlay, voice adapter | `WearModuleApp` authoritative local field |
| Scanner hardware/admission | scanner slice/policy | dispatcher/native adapter | UI orchestration/actual route alone |
| Connectivity coarse state | connectivity slice | network/native observer | reporter singleton as business owner |
| Status deadline | overlay/status slice + scheduler effect | projections | widget timer |
| UI dialog/input | bounded versioned UI effect state | phone UI | runtime `BuildContext` |
| Foreground service | native host adapter | lifecycle slice observation | business store inside service |

## 14. Миграционная стратегия

Нельзя заменить всё одним MR. Нужна strangler migration с сохранением работающего flow.

### Общий compatibility contract

На промежуточных этапах:

- aggregate shell существует как root envelope и очередь intents;
- для немигрированного value он публикует read-only adapted view текущего owner;
- один screen принадлежит максимум одному business handler;
- adapter не создаёт независимую mutable копию;
- старый API помечается deprecated до удаления;
- каждый MR уменьшает число mutable owners;
- ownership transfer происходит атомарно по value/slice;
- projection adapters не принимают business decisions.

## 15. Последовательность MR

### MR-S1. Store shell, immutable snapshot и version contract

Изменения:

- добавить immutable `WearRuntimeState` root envelope;
- добавить `WearRuntimeStore`, replayable current-state contract и идемпотентный `dispose()`;
- добавить последовательную dispatch queue;
- добавить `WearIntent`, `WearDispatchResult` и typed reject reasons;
- добавить `sessionEpoch`, `revision`, operation identity primitives;
- реализовать ADR-0002 commit/effect/receipt ordering и effect runner boundary;
- определить no-op, receipt и nested-dispatch semantics;
- обернуть текущий controller/runtime entry points compatibility facade-ом;
- публиковать legacy values только как read-only adapted snapshot;
- добавить provisional phone/glasses selectors поверх snapshot без удаления старых builders;
- запретить duplicate screen ownership в composite runtime.

Критический invariant MR-S1:

```text
ни одно business value не становится writable одновременно
в legacy owner и в aggregate shell
```

Shell не должен «синхронизировать» два stores. Он сериализует новые intents и адаптирует существующего owner до передачи конкретного slice.

Почему первым:

Без root/version/queue/receipt/execution contract последующие features будут мигрировать в разные формы, а scanner/native adapters не смогут единообразно подтверждать input.

Не входит:

- перенос printer/scan/availability ownership;
- изменение native scanner;
- изменение voice audio pipeline;
- изменение UI layout.

Тесты:

- новый subscriber немедленно получает current snapshot;
- state и nested collections immutable;
- stream закрывается после idempotent dispose;
- dispatch после terminal не мутирует state;
- revisions строго возрастают только при опубликованном изменении;
- no-op/rejected intent не увеличивает revision;
- tuple ordering корректно работает при новом epoch;
- dispatch receipt содержит accepted/rejected, epoch, revision и typed reason;
- loading/pending snapshot committed до effect start;
- effect scheduled до receipt completion;
- receipt не ждёт завершения blocked external effect;
- rejected intent не schedules effect;
- intents выполняются последовательно;
- nested dispatch ставится в хвост и не re-enter reducer;
- reducer error не блокирует очередь;
- terminal intent не ждёт unrelated slow effect;
- session reset supersede старые operation IDs;
- result старого epoch игнорируется;
- duplicate screen ownership отклоняется;
- read-only mirror совпадает с legacy owner;
- попытка записать в mirror отсутствует на API/compile boundary;
- compatibility snapshot не меняет существующий logical flow.

Stop/revert:

- если shell требует менять feature behavior, MR нужно разделить;
- если одновременно существуют два writable roots одного value, MR не готов;
- если revision увеличивается от повторного чтения/projection, contract нарушен;
- если barcode adapter не может отличить rejected intent от принятого, receipt contract недостаточен;
- если slow effect удерживает queue и блокирует terminal intent, ADR-0002 нарушен.

### MR-S2. Session identity, lifecycle и navigation slices

Изменения:

- перенести auth/session identity и lifecycle в aggregate slices;
- перенести logical/actual navigation, pending request/history;
- route observer отправляет intents;
- terminal lifecycle supersede epoch и operations;
- запретить новые direct writes в `WearSession` identity/lifecycle API;
- оставить printer selection временно legacy-owned через явно названный compatibility port до MR-S4.

Важно:

`WearSession` не объявляется целиком read-only, пока printer selection не передан в MR-S4. В MR-S2 read-only становится только уже мигрированная identity/lifecycle часть. Printer selection не копируется writable в aggregate заранее.

Почему до feature state:

Feature transitions должны сразу опираться на окончательный logical screen и session epoch.

Тесты:

- paused/hidden сохраняют runtime active;
- detached/logout supersede epoch;
- actual route может отставать;
- resume синхронизирует latest route ровно один раз;
- stale acknowledgement игнорируется;
- поздний authorization callback не оживляет terminal state;
- receipt старого logical screen rejected;
- legacy printer selection остаётся единственным owner до MR-S4.

### MR-S3. Voice, scanner и connectivity control slices

Изменения:

- перенести coarse voice phase/admission в voice slice;
- перенести scanner hardware lifecycle и barcode admission в scanner slice;
- перенести coarse connectivity observations в connectivity slice;
- `WearModuleApp`, scanner policy и reporters превратить в adapters/observers;
- native callbacks отправляют typed observation intents;
- scanner delivery использует `WearDispatchResult`;
- сохранить PCM/Vosk/audio lease вне aggregate state;
- не менять UAC4 transport или recognition algorithms.

Почему отдельным этапом:

Эти control states влияют на все feature slices и screen-off behavior, но не являются printer/scan/availability business data. Если оставить их в UI orchestration до конца, единый root будет неполным, а terminal/admission решения останутся раздвоенными.

Тесты:

- voice phase observation меняет только coarse slice;
- PCM/audio level не публикуют aggregate snapshots;
- commandsEnabled/voice admission соответствуют coarse state;
- scanner hardware prepared и barcode admission независимы;
- active/background route drift использует navigation + scanner slices;
- terminal state безусловно закрывает scanner/voice admission;
- поздний native voice/scanner callback старого epoch игнорируется;
- barcode receipt accepted/rejected корректно подтверждается dispatcher-у;
- connectivity observation versioned и stale observation не откатывает state;
- reporter/adapters не становятся writable owners.

### MR-S4. Printer vertical slice

Изменения:

- перенести printer phase/list/focus/white/yellow/selection в task slice;
- `WearPrinterRuntime` превратить в reducer/effect handler;
- удалить отдельный authoritative printer stream;
- убрать mutable printer selection из `WearSession`;
- legacy printer APIs сделать read-only facade или удалить;
- phone/glasses читают один migrated snapshot;
- load/reload возвращают versioned result intents.

Почему printer первым feature slice:

Flow короткий, dependencies ограничены, а selection уже почти вынесен из widget tree.

Тесты:

- load без widget tree;
- white и yellow различаются;
- focus одинаков на phone/glasses;
- selection переживает phone detach/attach;
- reload сохраняет валидную пару;
- reload обрабатывает исчезновение white/yellow;
- stale success и error после logout игнорируются;
- два select не создают две navigation/selection операции;
- touch/voice/button приводят к одинаковому state;
- repository search подтверждает отсутствие mutable `WearSession` printer copy.

### MR-S5. Scan, print и status slice

Изменения:

- перенести barcode delivery, lookup, duplicates, focus, print phase и status;
- navigation становится reducer transition + effect;
- timers заменить injectable scheduler effect;
- exactly-once print identity;
- убрать scan feature stream как authority;
- status хранить в одном overlay/status slice.

Тесты:

- zero/one/many products;
- duplicate selection;
- duplicate scanner delivery consumed once;
- stale lookup/print success и error игнорируются;
- повторный select во время print не печатает дважды;
- status deadline через fake clock;
- timer старого epoch не навигирует;
- printer -> scan -> print без widgets;
- phone/glasses projection parity.

### MR-S6. Availability slice

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

### MR-S7. Unified input intents и UI effects

Изменения:

- touch, voice, button, barcode преобразуются в одни semantic intents;
- удалить business callbacks из `WearScreenActionHandler` для мигрированных screens;
- manual input/settings/dialogs оформить bounded UI effects;
- effect result versioned;
- input adapters не могут менять state напрямую;
- удалить remaining legacy entry points, обходящие dispatch queue.

Тесты:

- touch/voice/button deep-equal final state;
- один barcode path;
- UI effect delivered once при rebuild/reconnect;
- acknowledgement удаляет effect;
- stale UI result rejected;
- queue bound/one-per-kind соблюдается;
- inactive phone выполняет documented defer/alternative/reject;
- command старого screen ignored;
- очередь сохраняет порядок.

### MR-S8. Единственная projection pipeline

Изменения:

- phone selectors и glasses projector строятся из aggregate snapshot;
- transport envelope получает epoch/revision;
- убрать legacy feature-owned glasses payload callbacks и caches как source;
- reconnect отправляет latest snapshot;
- status/voice overlay versioned;
- удалить provisional projection adapters MR-S1.

Тесты:

- golden payload каждого screen/step;
- deterministic projection;
- phone/glasses focus parity;
- revision 10 не перезаписывается revision 9 в одном epoch;
- новый epoch принимает revision 1 и отклоняет старый epoch;
- reconnect latest snapshot;
- старый overlay не перекрывает новый screen;
- projection read не увеличивает state revision.

### MR-S9. Удаление compatibility layer

Удалить:

- mutable static `WearSession`;
- feature authoritative streams;
- nullable runtime setters;
- screen payload cache как source of truth;
- hard-coded migrated-screen checks;
- business `enterScreen()` из widgets;
- ненужные presentation-state bridges;
- оставшиеся screen-owned business callbacks;
- duplicate actual-screen owner;
- read-only mirrors, больше не нужные consumers.

Тесты/gates:

- repository search не находит запрещённые mutation paths;
- ownership ledger не содержит временных owners;
- полный automated suite;
- T2151 acceptance;
- logout/detached resource release;
- screen-off printer/scan/availability scenarios;
- docs отражают фактический final state.

## 16. Test strategy

### 16.1 Reducer tests

Чистые таблицы:

```text
state + intent -> expected state + effects + receipt
```

Проверять happy path, invalid/stale intent и no-op revision behavior.

### 16.2 Store serialization tests

Проверять конкурентные inputs, nested result dispatch, очередь после exception, receipt semantics, commit/effect order, dispose и monotonic versions.

### 16.3 Effect-handler tests

Fake repositories, printer, camera, scanner, clock и navigation output.

Success и error используют одинаковую admission function. Независимые effects могут завершаться out of order; exclusive resource имеет отдельную policy.

### 16.4 Projection tests

Golden/structural tests для phone view model и glasses payload. Projection read не мутирует revision.

### 16.5 Contract tests

- capability означает реальное исполнение;
- barcode admission означает, что handler готов;
- dispatch receipt соответствует фактическому принятию intent;
- effect стартует после commit expected operation identity;
- slow effect не блокирует terminal queue;
- каждый screen имеет максимум одного owner;
- каждый value имеет максимум одного writable owner;
- read-only mirror совпадает с source owner;
- UI effect имеет exactly-once acknowledgement и bounded pending state;
- result identity проверяется единообразно;
- high-frequency PCM/audio level не попадает в aggregate state.

### 16.6 Integration tests без widget tree

Критические printer/scan/availability flows должны проходить при `phoneUiActive=false`.

### 16.7 Widget tests

Проверяют только:

- selector rendering;
- intent dispatch;
- UI effect handling;
- route observation.

Не должны быть единственным доказательством business flow.

### 16.8 Hardware tests

T2151:

- 20+ barcode scans screen-off;
- 30 минут PCM без aggregate snapshot на каждый packet/level;
- Firebird через 5/30 минут screen-off;
- photo capture/delete;
- printer flow;
- availability flow;
- resume route synchronization;
- logout/detached teardown.

## 17. Per-MR proof requirements

Каждый кодовый MR обязан отвечать на вопросы:

1. Какое mutable ownership удалено?
2. Какой один owner остаётся для каждого value?
3. Есть ли read-only mirror и когда он удаляется?
4. Какие intents добавлены?
5. Каков dispatch receipt для accepted/rejected paths?
6. Какие effects добавлены?
7. В каком порядке выполняются commit/effect/receipt?
8. Какова concurrency/exclusive policy effects?
9. Как success и error защищены epoch/operationId?
10. Что происходит при screen change?
11. Что происходит при logout/detached/dispose?
12. Совпадают ли phone и glasses projection?
13. Меняется ли revision только от state mutation?
14. Не попал ли high-frequency transport в aggregate state?
15. Какие tests доказывают invariant?
16. Как безопасно откатить MR?

Шаблон: [`checklists/WEAR_SINGLE_STATE_MR_REVIEW.md`](checklists/WEAR_SINGLE_STATE_MR_REVIEW.md).

## 18. Запреты на период миграции

Не принимать MR, который:

- добавляет новый mutable singleton;
- добавляет feature stream без плана удаления;
- вводит dual write legacy + aggregate;
- делает read-only mirror writable;
- читает actual route для business decision;
- запускает business load только из widget lifecycle;
- дублирует touch и voice business logic;
- использует `Object?` там, где это новый cross-layer contract;
- применяет async success/error без identity;
- не даёт adapter-у typed accepted/rejected receipt;
- стартует effect до commit expected operation identity;
- удерживает dispatch queue до завершения slow external effect;
- меняет state и отправляет glasses payload двумя независимыми путями;
- хранит UI effects без bound/ack policy;
- кладёт PCM chunks/audio level/native objects в aggregate state;
- не имеет terminal/idempotent dispose contract;
- переносит business logic в foreground service;
- смешивает state migration с UAC4/PCM refactoring без необходимости.

## 19. Наблюдаемость

В процессе миграции полезно логировать структурированно:

```text
sessionEpoch
stateRevision
intentType
dispatchAccepted/rejectReason
logicalScreen
actualPhoneScreen
operationId
effectType
effectScheduled/completed
result accepted/rejected reason
owner/source adapter
terminal/disposed
```

Не логировать чувствительные auth payloads или персональные данные пользователя.

Для rejected stale result причина должна быть различима:

```text
wrong epoch
wrong operation id
wrong task phase
terminal runtime
superseded screen
unsupported command
duplicate delivery
acknowledged UI effect
```

## 20. Rollback strategy

Каждый vertical slice должен быть откатываемым отдельно.

Правила:

- schema aggregate root расширяется совместимо;
- adapter удаляется только после полного slice migration;
- нельзя одновременно менять repository/native protocol и ownership без необходимости;
- before/after behavior фиксируется contract tests;
- hardware-specific изменения отделяются от pure Dart state changes;
- при regression возвращается предыдущий owner, а не создаётся третий state holder;
- rollback обновляет ownership ledger.

## 21. Definition of Done

Переход завершён, когда одновременно выполнено:

1. существует один authoritative `WearRuntimeState` на живую сессию;
2. только `dispatch(WearIntent)` меняет business-state;
3. dispatch возвращает typed accepted/rejected receipt;
4. store имеет replayable current state и terminal/idempotent dispose;
5. commit/effect/receipt order соответствует ADR-0002;
6. slow effects не блокируют unrelated/terminal intents;
7. каждый snapshot имеет определённую `(sessionEpoch, revision)` semantics;
8. state и collections immutable;
9. no-op intent не создаёт новую revision;
10. каждый async result имеет epoch/operation identity;
11. success и error проходят одинаковый stale guard;
12. logical screen управляет commands, scanner и glasses;
13. actual phone route является observation;
14. session, voice, scanner и connectivity control имеют aggregate owners;
15. PCM/audio transport остаётся вне aggregate state;
16. phone и glasses строятся из одного snapshot;
17. feature runtimes не владеют отдельными authoritative streams;
18. widgets не запускают business flow из lifecycle;
19. UI-only действия оформлены bounded effects с acknowledgement;
20. foreground service не владеет Dart state;
21. logout/detached окончательно закрывают resources/admission;
22. printer/scan/availability проходят без widget tree;
23. automated и hardware gates зелёные;
24. legacy owners и compatibility adapters удалены;
25. ownership ledger пуст от временных записей;
26. canonical docs соответствуют коду.

## 22. Ближайшее действие

После принятия этого документа следующий кодовый MR — **MR-S1: Store shell, immutable snapshot и version contract**.

Он должен быть намеренно небольшим: root envelope, replayable stream/dispose, intent/receipt base, serialization, commit/effect ordering, epoch/revision и read-only compatibility adapters без переноса feature behavior.

Главное доказательство MR-S1 — не количество новых классов, а отсутствие второго writable owner и отсутствие блокировки input queue внешними effects. Любое legacy value либо остаётся legacy-owned и только отражается read-only, либо передаётся aggregate slice атомарно в отдельном migration MR.
