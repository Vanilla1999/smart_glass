# ADR-0001: Один владелец состояния Wear runtime

- Статус: принято для поэтапной реализации
- Дата: 2026-08-23
- Область: `lib/modules/wear`
- Связанный план: [`../WEAR_SINGLE_STATE_RUNTIME_PLAN.md`](../WEAR_SINGLE_STATE_RUNTIME_PLAN.md)

## Контекст

Wear-модуль одновременно отображается на телефоне и очках и принимает команды из нескольких источников:

- touch UI телефона;
- голос;
- аппаратные кнопки очков;
- barcode scanner;
- native callbacks;
- async-результаты Firebird, печати и фотоконтроля.

Исторически состояние распределено между `WearFlowController`, feature runtimes, `WearSession`, screen action handlers, Flutter route, локальными Cubit/Provider и кэшами glasses payload. Это создаёт несколько независимых ответов на одни и те же вопросы:

- какой бизнес-экран активен;
- какой item выбран;
- разрешён ли barcode;
- какая команда допустима;
- что должен показать телефон;
- что должны показать очки;
- относится ли async-result к текущей сессии.

Стабилизационный MR #1 устранил доказанные гонки barcode/scanner/runtime readiness, но не сделал state единым. Без явного решения следующая миграция снова может создать параллельный state holder.

## Решение

Целевое состояние одной живой Wear-сессии — ровно один authoritative aggregate state:

```text
WearRuntimeState
```

Целевая единственная mutation boundary:

```text
WearRuntimeStore.dispatch(WearIntent)
```

Телефон и очки не синхронизируют состояние друг с другом. Оба являются проекциями одного snapshot:

```text
inputs -> WearIntent -> WearRuntimeStore -> WearRuntimeState
                                      |-> phone projection
                                      |-> glasses projection
```

### Переходное правило миграции

Переход выполняется по slices, поэтому до завершения roadmap старые owners ещё существуют. Это не разрешает две writable копии одного значения.

Для каждого business value в любой момент допускается ровно один writable owner:

```text
legacy owner -> атомарная передача ownership -> aggregate slice
```

Пока slice не мигрирован:

- legacy component остаётся единственным writable owner;
- aggregate store может публиковать только read-only adapted view этого значения;
- запись в mirror запрещена;
- adapter не хранит самостоятельную mutable копию;
- phone/glasses могут читать mirror, но business decision продолжает принимать текущий объявленный owner.

В MR, который передаёт ownership:

1. aggregate slice становится единственным writable owner;
2. legacy API превращается в read-only projection/deprecated facade либо удаляется;
3. запись в оба места даже временно в одном commit запрещена;
4. tests доказывают отсутствие расходящихся копий.

Таким образом, migration shell не считается вторым store: он либо оборачивает существующего owner, либо владеет уже перенесённым slice, но не конкурирует с ним.

### Авторитетные понятия

- `logicalScreen` — бизнес-экран и источник истины для команд, scanner admission и glasses projection;
- `actualPhoneScreen` — наблюдение о реально построенном Flutter route, но не business authority;
- `pendingNavigation` — запрос догнать logical state при доступном phone UI;
- `sessionEpoch` — идентификатор поколения Wear-сессии в пределах жизни store/process;
- `revision` — монотонная версия опубликованного aggregate snapshot внутри epoch;
- `operationId` — идентификатор async effect внутри `sessionEpoch`.

Порядок transport snapshots сравнивается по паре:

```text
(sessionEpoch, revision)
```

При новом epoch revision может начаться заново. Snapshot старого epoch всегда stale независимо от его revision.

No-op intent не публикует новый snapshot и не увеличивает revision. Любое реальное изменение state, включая регистрацию ожидаемой async-операции или pending UI effect, публикует новую revision.

### Разрешённые feature-компоненты

Printer, scan и availability компоненты могут оставаться отдельными reducer/effect-handler классами, но не могут владеть независимым authoritative stream или копией бизнес-state после передачи соответствующего slice.

Они получают state slice и intent/effect result и возвращают новый slice либо следующий intent.

### Что остаётся локальным UI-state

В aggregate state не обязаны попадать:

- `ScrollController`;
- animation controller;
- временная геометрия layout;
- локальная подсветка нажатия;
- незавершённый draft ввода до submit;
- высокочастотный audio level;
- сырые PCM chunks.

Локальный state допустим только если он:

1. не меняет бизнес-решение;
2. не отображается одновременно на телефоне и очках;
3. не нужен после уничтожения widget;
4. не участвует в voice grammar, scanner admission или navigation.

Если draft должен пережить уничтожение widget, влиять на очки или участвовать в voice flow, он уже не локальный и должен стать aggregate slice либо versioned UI effect state.

### UI-only операции

Операции, требующие `BuildContext` или системного UI, оформляются как versioned `WearUiEffect`, например:

- запросить ручной ввод;
- открыть системные Wi-Fi settings;
- показать диалог;
- запросить разрешение.

UI исполняет effect и возвращает typed result с `effectId` и `sessionEpoch`. Runtime не вызывает `BuildContext` напрямую.

Pending UI effects являются bounded state, а не бесконечным event log:

- effect имеет stable ID;
- хранится до acknowledgement/cancel/supersede;
- повторная подписка UI не создаёт второй effect;
- acknowledged effect удаляется атомарно;
- effects старого epoch удаляются при reset;
- количество pending effects ограничено явным контрактом.

### Android foreground service

`WearControlForegroundService` не владеет Dart business-state и не создаёт второй Flutter engine. В Variant A он остаётся host/liveness adapter для живых process, `MainActivity` и основного Flutter engine.

Уничтожение process или engine завершает сессию; восстановление headless state в это решение не входит.

## Почему выбран этот вариант

### Один store вместо синхронизации нескольких stores

Синхронизация нескольких state holders требует протокола разрешения конфликтов. Для локального business flow это сложнее и менее надёжно, чем один сериализованный владелец.

### Logical screen вместо Flutter route

При screen-off logical transition может завершиться без построения нового Flutter widget. Следовательно, route не может определять voice grammar, barcode admission или состояние очков.

### Snapshot + revision вместо отдельных payload callbacks

Phone и glasses projection, построенные из одного versioned snapshot, можно сравнивать, тестировать как чистые функции и отбрасывать при stale `(sessionEpoch, revision)`.

### Typed intent/effect вместо screen callbacks

Touch, voice, button и scanner должны приводить к одному semantic intent. Это устраняет разные бизнес-реализации одной команды и зависимость runtime от widget lifecycle.

## Последствия

Положительные:

- один источник истины для каждого перенесённого business value;
- детерминированный порядок mutation;
- одинаковое поведение touch/voice/button/scanner;
- phone и glasses можно проверять на одной revision;
- stale async result формально отклоняется;
- screen-off flow не зависит от widget tree;
- проще property и state-machine tests.

Стоимость:

- потребуется временный read-only compatibility layer;
- feature runtimes придётся превратить из владельцев state в reducer/effect handlers;
- часть screen callbacks будет заменена UI effects;
- статический `WearSession` нужно по slices сделать read-only adapter, затем удалить;
- старые тесты придётся перевести с внутренних streams на aggregate snapshots;
- на переходных этапах ownership matrix должна документироваться в каждом MR.

## Запрещённые обходы

До завершения миграции нельзя:

- добавлять новый mutable singleton с Wear business-state;
- добавлять новый feature state stream как второй source of truth;
- делать read-only mirror writable «временно»;
- выполнять dual write в legacy owner и aggregate slice;
- считать Flutter route authoritative;
- менять business-state напрямую из widget lifecycle;
- выполнять одну и ту же бизнес-команду отдельно в touch и voice path;
- принимать async success или error без проверки `sessionEpoch` и `operationId`;
- формировать glasses business payload из widget state;
- хранить UI effects как неограниченный event history;
- переносить Dart business-state в Android foreground service.

## Критерий завершения решения

ADR считается реализованным, когда:

1. все business mutations проходят через `dispatch(WearIntent)`;
2. aggregate state имеет `sessionEpoch` и `revision` с определённой tuple-семантикой;
3. phone и glasses projections строятся из одного snapshot;
4. feature runtimes не публикуют независимые authoritative states;
5. widget `initState()` не запускает бизнес-переход;
6. старый async success/error не способен изменить новую сессию;
7. pending UI effects bounded и exactly-once acknowledged;
8. полный printer/scan/availability flow проходит без построенного phone widget tree;
9. logout и terminal lifecycle окончательно закрывают admission и resources;
10. compatibility mirrors либо удалены, либо доказуемо read-only.

## Пересмотр решения

ADR следует пересмотреть только если появится подтверждённое требование переживать уничтожение Flutter engine или process. Тогда потребуется отдельное решение о persistent state, headless engine/process isolation и восстановлении effect journal; это не должно внедряться как скрытое расширение Variant A.
