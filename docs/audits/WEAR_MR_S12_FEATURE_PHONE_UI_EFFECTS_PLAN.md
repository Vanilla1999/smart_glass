# MR-S12: Aggregate feature phone projection and bounded UI effects

Дата: 2026-08-24.

## 1. Контекст

- Integration branch: `experiment/aligned-audio-frontend`.
- Base commit: `7e7181a16aefaf67e2aa01de2fdae0e3c80ea048`.
- Work branch: `refactor/wear-feature-phone-ui-effects`.
- Предыдущий этап: PR #16 / MR-S11 — aggregate logical navigation,
  route-observation boundary, scanner/barcode/voice screen attribution.
- Нормативные документы:
  - `docs/WEAR_SINGLE_STATE_RUNTIME_PLAN.md`;
  - `docs/decisions/ADR-0001-WEAR_SINGLE_STATE_OWNER.md`;
  - `docs/decisions/ADR-0002-WEAR_STORE_EXECUTION_ORDER.md`.

После MR-S11 logical screen и внешние input boundaries уже aggregate-owned.
Однако часть phone feature UI всё ещё получает business data из compatibility
surfaces:

- product-select читает route `WearProductSelectArgs` и
  `WearScanRuntime.stateStream`;
- scan-idle читает `WearScanRuntimeState` и открывает manual input напрямую из
  widget callback;
- manual input result вызывает controller barcode callback вместо typed aggregate
  UI-effect completion;
- status screen предпочитает route args даже когда scan status уже authoritative
  в aggregate task slice.

Это не создаёт второй feature reducer, но оставляет несколько независимых ответов
на вопросы «какие товары сейчас выбираются», «какой focus committed» и «какой
status должен показать phone».

## 2. Цель

Перевести migrated scan phone screens на один committed aggregate snapshot и
сделать manual barcode input bounded UI effect:

```text
WearRuntimeState
  -> pure scan phone projection
  -> scan-idle / product-select / scan-status rendering

ManualInputRequested
  -> pending WearUiEffect(manualBarcodeInput)
  -> phone claims exact effectId
  -> UI input route
  -> completed(value) / cancelled
  -> aggregate reducer accepts/rejects result
  -> typed barcode transition
```

## 3. Ownership ledger

| Business value | Owner до MR | Owner после MR | Retained compatibility |
|---|---|---|---|
| Scan phone phase/loading | Aggregate scan slice, phone reads runtime adapter | Aggregate scan slice + pure selector | `WearScanRuntime` remains input-only adapter until final cleanup |
| Product list/barcode | Aggregate scan slice plus route args | Aggregate scan slice only | route-extra compatibility removed for product-select |
| Product focus | Aggregate scan slice plus widget cache/runtime stream | Aggregate scan slice only | widget cache is render/scroll-only |
| Scan status | Aggregate scan slice plus route args | Aggregate scan status for migrated scan status | generic non-scan status args remain bounded compatibility |
| Manual input request | widget-local bool + direct route | Aggregate pending `WearUiEffect` | Flutter route is UI executor only |
| Manual input result | direct controller barcode callback | claimed effect completion -> aggregate barcode transition | none |

## 4. Scope реализации

### 4.1. Pure feature phone projection

Добавить immutable pure selector над `WearRuntimeState`, содержащий только данные,
которые нужны phone scan screens:

- `(sessionEpoch, revision)`;
- logical screen;
- scan phase;
- barcode;
- immutable products;
- focused index;
- product name;
- loading text/icon;
- authoritative scan status;
- selected printer snapshot, если он действительно нужен render layer.

Projection:

- не мутирует store;
- не увеличивает revision;
- не читает Flutter route args;
- нормализует focus относительно committed product list;
- использует тот же aggregate task, что glasses projection.

### 4.2. Product-select phone screen

1. Удалить business dependency на `WearProductSelectArgs` и
   `WearScanRuntime.stateStream`.
2. Подписаться на `WearRuntimeAuthority.states`.
3. Рендерить products/barcode/focus из pure aggregate projection.
4. Widget-local focus оставить только как scroll/render cache; touch/voice focus
   сначала проходит typed aggregate input и отображается после committed snapshot.
5. Selection должна использовать product из текущего committed list и не принимать
   stale route object.
6. Dynamic voice items должны строиться из текущего aggregate product list.
7. Удалить route-extra ownership для product-select.

### 4.3. Scan-idle phone screen

1. Удалить `WearScanRuntimeState` subscription.
2. Рендерить waiting/loading/printing/status data из aggregate projection.
3. Кнопка manual input не открывает route напрямую и не хранит business-open flag.
4. Она dispatches `requestUiEffect(manualBarcodeInput)` с captured epoch/screen.
5. Rebuild/repeated tap не создаёт второй pending effect.

### 4.4. UI-effect executor

Добавить phone-side consumer, предпочтительно в `WearModuleApp`, который:

1. наблюдает aggregate pending UI effects;
2. исполняет только effect текущего epoch и logical screen;
3. atomically claims exact `effectId` до открытия UI;
4. открывает manual barcode route через phone router;
5. отправляет `completeUiEffect(effect, value)` или `cancelUiEffect(effect)`;
6. не повторяет claimed effect при rebuild/reconnect;
7. отменяет stale effect после screen/epoch change;
8. не вызывает controller business callback напрямую.

### 4.5. Manual input completion reducer

`WearUiEffectCompleted` для `manualBarcodeInput` должен:

- требовать previously claimed effect;
- проверить exact epoch/effect/screen;
- удалить pending effect атомарно;
- при non-empty String применить тот же scan barcode reducer, что hardware barcode;
- при empty/null завершить effect без feature mutation;
- не потерять effects scan lookup;
- stale/error/cancel path не запускает lookup.

### 4.6. Status and routes

1. Scan status phone rendering предпочитает aggregate scan status.
2. Generic auth/other status может временно использовать route args, но не
   конкурирует с aggregate scan task.
3. Product-select и scan-idle route builders не требуют business snapshots в
   `extra`.
4. Navigation effects могут сохранять UI-only extra только там, где aggregate
   slice ещё не содержит данных.

## 5. Tests/specifications

Добавить статические и reducer/property specifications:

1. product-select и scan-idle не импортируют `wear_scan_runtime.dart` и не
   подписываются на feature runtime stream;
2. product list/barcode/focus phone projection равны committed scan slice;
3. projection read не меняет revision;
4. widget не читает `WearProductSelectArgs` как business owner;
5. touch/voice focus не меняет local cache до aggregate commit;
6. duplicate manual-input request создаёт один effect;
7. inactive phone не claim'ит effect;
8. claimed manual input completed with barcode запускает exactly one scan lookup;
9. cancel/empty result удаляет effect без lookup;
10. stale epoch/screen/effect completion rejected;
11. rebuild не исполняет claimed effect второй раз;
12. scan status screen uses aggregate status before route compatibility args;
13. route builders no longer require product/scan business snapshots.

## 6. Не входит

- перенос voice-clarification args/focus/notice;
- перенос transient voice-search overlay;
- физическое удаление `WearFlowState` и всего facade;
- перенос auth badge handler в aggregate effect;
- изменение UAC4/PCM/Vosk/native scanner;
- repository/API protocol changes;
- UI layout redesign;
- Flutter/analyzer/Gradle/build/device execution.

Эти границы закрываются последовательно:

- MR-S13 — aggregate voice clarification + transient overlay;
- MR-S14 — физическое удаление `WearFlowState`/facade/legacy status paths;
- MR-S15 — final ownership gates, docs and release evidence boundary.

## 7. Review checklist

- Phone scan UI читает один aggregate snapshot.
- Route args не могут переопределить committed product/status/focus.
- UI effect claim происходит до route open.
- Completion относится к exact effect and epoch.
- Completion не теряет scan reducer effects.
- Repeated tap/rebuild не открывает второй manual input.
- Screen change/logout cancels or rejects stale UI result.
- No `BuildContext` enters runtime/reducer.
- No new feature stream/state holder.
- Diff не касается audio/native/build artifacts.

## 8. Validation limitation

По ограничению владельца не запускаются:

- `flutter test`;
- `flutter analyze` / `dart analyze`;
- Gradle;
- APK/build;
- emulator/device tests.

Validation состоит из полного GitHub diff review, call-graph/type inspection и
committed regression specifications. Исполняемая проверка остаётся owner-run
release gate.

## 9. Stop/revert

MR нужно разделить, если manual-input effect требует одновременно переносить
voice clarification/transient overlay либо менять scanner/native protocol.

Rollback возвращает phone screens к read-only compatibility adapter одним
revert, не создавая третьего writable owner.
