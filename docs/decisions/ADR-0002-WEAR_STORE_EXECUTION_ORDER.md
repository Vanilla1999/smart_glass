# ADR-0002: Порядок выполнения Wear store, effects и receipt

- Статус: принято для реализации MR-S1
- Дата: 2026-08-23
- Область: `WearRuntimeStore`
- Базовое ownership-решение: [`ADR-0001-WEAR_SINGLE_STATE_OWNER.md`](ADR-0001-WEAR_SINGLE_STATE_OWNER.md)
- Roadmap: [`../WEAR_SINGLE_STATE_RUNTIME_PLAN.md`](../WEAR_SINGLE_STATE_RUNTIME_PLAN.md)

## Контекст

Даже при одном state owner возможны разные и несовместимые semantics:

- завершать `dispatch()` до публикации snapshot или после;
- запускать effect до фиксации ожидаемого `operationId` или после;
- выполнять nested dispatch re-entrantly или через очередь;
- сериализовать все effects либо разрешать конкурентность;
- считать stream обычным broadcast либо replayable state stream;
- принимать intents после teardown либо бросать исключение.

Если это не зафиксировать до MR-S1, scanner acknowledgement, exactly-once print и stale-result tests будут зависеть от случайной реализации.

## Решение

### Store API

Целевой минимальный контракт:

```dart
abstract interface class WearRuntimeStore {
  WearRuntimeState get state;
  Stream<WearRuntimeState> get states;

  Future<WearDispatchResult> dispatch(WearIntent intent);
  Future<void> dispose();
}
```

### State stream

`states` является state stream, а не только event stream:

- `state` всегда содержит последний committed snapshot;
- новый subscriber получает current snapshot без ожидания следующей mutation;
- одна committed revision публикуется не более одного раза как authoritative state event;
- projection/read не создаёт новую revision;
- после terminal dispose stream закрывается;
- после закрытия store не может быть повторно активирован.

Конкретная реализация может использовать собственный replay wrapper, synchronous initial emission или другой механизм, но observable contract должен быть одинаковым.

### Порядок обработки одного intent

Для каждого intent store выполняет шаги в таком порядке:

1. Ставит intent в единственную dispatch queue.
2. Когда intent становится head, читает один current immutable snapshot.
3. Reducer вычисляет:
   - next state или no-op;
   - список effects;
   - accepted/rejected receipt data.
4. Если state изменён, store атомарно:
   - присваивает next revision;
   - обновляет `state`;
   - публикует committed snapshot.
5. Store регистрирует/schedules effects, уже описанные committed state через expected `operationId` или pending effect identity.
6. Store завершает `Future<WearDispatchResult>`.
7. Переходит к следующему intent.

Следствия:

- effect не стартует до того, как state способен распознать его result;
- receipt не подтверждает intent до commit/scheduling boundary;
- receipt не ждёт завершения внешнего effect;
- subscriber не видит effect result до loading/pending snapshot;
- rejected/no-op intent не публикует новую revision.

### Reducer failure

Неожиданное исключение reducer/queue infrastructure:

- не публикует частичный snapshot;
- завершает receipt текущего intent контролируемой ошибкой или typed internal rejection согласно MR-S1 policy;
- обязательно снимает processing guard;
- не блокирует последующие intents;
- логируется без чувствительных данных.

Обычные business rejection (`busy`, `staleScreen`, `unsupported`, `duplicate`) не являются исключениями и возвращаются typed receipt.

### Nested dispatch

Nested dispatch запрещён re-entrantly.

Если reducer/effect adapter вызывает `dispatch()` во время обработки другого intent:

- новый intent добавляется в хвост той же очереди;
- current reducer завершается на исходном snapshot;
- nested intent получает snapshot после current commit;
- порядок стабилен и проверяется тестом.

Reducer в идеале возвращает effects, а не вызывает dispatch напрямую. Result effect всё равно возвращается через общую очередь.

### Effect mutation boundary

Effect handler не имеет setter-доступа к store state.

Он может только:

1. прочитать immutable effect payload;
2. вызвать repository/native/API;
3. отправить typed success/error result intent.

Callback, который напрямую меняет slice, нарушает ADR-0001.

### Конкурентность effects

Dispatch/reducer всегда сериализован. Effects не обязаны глобально выполняться последовательно.

Допускается конкурентность, если:

- каждый effect имеет `sessionEpoch + operationId`;
- state хранит ожидаемую identity;
- out-of-order result безопасно отклоняется;
- effects не используют один exclusive resource без coordinator;
- exactly-once effects имеют dedupe/mutex policy.

Обязательная сериализация или mutual exclusion требуется как минимум там, где resource/protocol этого требует, например:

- одна print operation для одного task;
- одна photo capture lease;
- scanner hardware prepare/pause transition;
- navigation delivery одного pending request;
- один UI effect определённого one-per-kind типа.

Выбор concurrency policy фиксируется отдельно для каждого effect в MR и тестах. Нельзя случайно получить глобальную последовательность только из-за `await` в store queue, потому что медленный network effect тогда заблокирует голос, back и terminal intents.

### Out-of-order completion

Если operation `N+1` supersede operation `N`, result `N` отклоняется даже если завершился позже.

Проверяется одинаково для success и error:

```text
result.epoch == state.epoch
result.operationId == expectedOperationId
state phase допускает result
runtime не terminal
```

### Dispatch receipt

Receipt описывает обработку input intent, а не итог effect:

```text
accepted
sessionEpoch
revision
rejectReason
```

Примеры:

- barcode принят и lookup запущен → `accepted=true`, loading revision;
- barcode пришёл на duplicate-selection → `accepted=false`, reason `unsupportedInCurrentState`;
- повторный delivery → `accepted=false` или accepted-existing-operation по заранее выбранной policy;
- print intent принят → receipt не означает, что печать завершилась успешно;
- stale effect result → `accepted=false`, reason `staleOperation`.

Scanner/native adapter подтверждает delivery на основании receipt policy, а не на основании того, что callback был вызван.

### Terminal и dispose

`dispose()`:

- идемпотентен;
- немедленно переводит store в terminal admission state либо гарантирует эквивалентную terminal barrier;
- supersede active operations/effects;
- закрывает input admission;
- освобождает subscriptions/timers/effect runners;
- закрывает state stream после последнего допустимого terminal snapshot;
- не ждёт бесконечно зависший внешний effect, если его нельзя физически отменить;
- игнорирует его поздний result через epoch/terminal guards.

После начала terminal dispose:

- новый `dispatch()` не мутирует state;
- он возвращает typed terminal rejection либо согласованную disposed error policy;
- поздний auth/voice/scanner/route callback не создаёт новый runtime;
- повторный `dispose()` безопасен.

Точная публичная policy `typed rejection` против `StateError after stream close` выбирается в MR-S1, но должна быть одна для всех callers и покрыта тестами. До физического закрытия предпочтителен typed terminal receipt, чтобы adapters могли завершить pending delivery без исключений.

## Почему не сериализуем все effects через dispatch queue

Если store держит queue до завершения repository/native effect:

- медленный Firebird блокирует back/home/logout;
- terminal intent не может быстро закрыть admission;
- voice inputs копятся за network operation;
- scanner delivery timeout может истечь;
- unrelated features искусственно зависят друг от друга.

Поэтому queue сериализует state transitions, а effects исполняются отдельно и возвращают versioned results.

## Обязательные тесты MR-S1

### State stream

- новый subscriber сразу получает current snapshot;
- committed revision публикуется один раз;
- no-op не публикуется;
- stream закрывается после dispose.

### Commit/effect/receipt order

- effect видит уже committed expected operation ID;
- loading snapshot опубликован до effect result;
- receipt завершается после commit/schedule, но до завершения blocked effect;
- rejected intent не schedules effect.

### Queue

- concurrent intents имеют детерминированный порядок;
- nested dispatch идёт в хвост;
- reducer exception не блокирует очередь;
- terminal intent не ждёт медленный unrelated effect.

### Effect concurrency

- две разрешённые независимые операции могут завершиться в обратном порядке;
- stale result старой operation отклоняется;
- exclusive effect не запускается дважды;
- success/error используют один admission guard.

### Dispose

- dispose идемпотентен;
- dispatch после terminal не мутирует state;
- pending receipt завершается;
- поздний effect result игнорируется;
- stream/subscriptions закрываются;
- зависший fake effect не мешает terminal barrier.

## Последствия

Положительные:

- scanner получает честный и быстрый acknowledgement;
- loading state существует до external call;
- back/logout не блокируются network effect;
- out-of-order completion безопасен;
- teardown имеет проверяемую границу;
- store stream ведёт себя как state, а не случайный broadcast событий.

Стоимость:

- нужен отдельный effect runner/coordinator;
- нужны operation identities и per-resource policies;
- тесты очереди сложнее обычных controller tests;
- нельзя скрывать external call внутри reducer method.

## Запрещённые реализации

- `await repositoryCall()` внутри dispatch queue до следующего intent;
- effect, который напрямую вызывает state setter;
- effect start до commit expected operation ID;
- receipt `accepted=true` до reducer validation;
- broadcast stream без current snapshot contract;
- nested reducer re-entry;
- `dispose()` без terminal barrier;
- глобальная effect serialization без доказанной необходимости;
- success и error с разными stale guards.
