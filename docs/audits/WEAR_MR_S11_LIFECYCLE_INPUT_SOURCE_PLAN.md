# MR-S11: Widget lifecycle and aggregate input source

Дата: 2026-08-24.

## Контекст

- Integration branch: `experiment/aligned-audio-frontend`.
- Base commit: `7f9e0deafc4633c51ee4b77f70794044fe44e4cc`.
- Work branch: `refactor/wear-lifecycle-input-source`.
- MR-S10 перенёс focus четырёх phone screens в aggregate projection, но widgets всё ещё запускают compatibility `enterScreen()` из `initState()`, а часть input routing может получать business screen через controller compatibility view.

## Цель

Отделить построение Flutter route от business transition:

1. widgets не вызывают `enterScreen()` из lifecycle;
2. route observer остаётся observation actual phone route;
3. logical screen из `WearRuntimeState.navigation.logicalScreen` является единственным source для scanner/barcode/voice admission;
4. widget attachment не может повторно запустить load, сбросить focus или отменить активную operation;
5. screen-off flow не зависит от widget tree.

## Ownership

| Value | До MR | После MR |
|---|---|---|
| Logical business screen | Aggregate, но compatibility widgets повторно вызывают `enterScreen()` | Только aggregate navigation intents/transitions |
| Actual Flutter route | Route observation | Route observation, без business mutation |
| Barcode source screen | Compatibility controller view в оставшемся path | Aggregate `navigation.logicalScreen` |
| Widget lifecycle | Может инициировать business entry | Только subscriptions, UI handlers и observation |

## Scope

- удалить business `enterScreen()` из phone widget `initState()`/resume paths;
- перевести barcode/input source на aggregate logical screen;
- сохранить explicit user actions, которые действительно отправляют navigation intent;
- добавить repository gates и focused behavior specifications;
- не удалять весь `WearFlowState`/controller в этом MR — это MR-S12;
- не менять UAC4, PCM, scanner native protocol, repositories или layout.

## Static acceptance

- production presentation files не содержат lifecycle-вызовов `.enterScreen(`;
- barcode dispatcher не читает `flowController.state.screen`;
- actual route не используется для business admission;
- navigation выполняется typed aggregate intent;
- widget creation не запускает feature load;
- retained compatibility API явно классифицирован как orchestration only;
- no Flutter/analyzer/Gradle/build commands are run.

## Review workflow

Plan commit → implementation → PR → full static review → review fixes → second review → merge → branch cleanup.
