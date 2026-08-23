# MR-S11 static review findings

Дата: 2026-08-24.

Первый exact-head review PR #16 подтвердил направление MR-S11, но нашёл
блокирующие gaps до merge:

1. `WearFlowController` всё ещё использовал `WearFlowState.screen` в production
   capability, barcode, phrase и command attribution paths вместо aggregate
   `logicalScreen`.
2. `WearVoiceApplicationDispatcher` захватывал screen через
   `_flow.state.screen`, поэтому voice event мог относиться к compatibility
   mirror, а не к committed aggregate snapshot.
3. Pre-auth unsupported-barcode fallback не был ограничен anonymous
   `WearScreenId.main`.
4. `WearMainScreen` мог инициировать logical menu navigation из widget attachment.
5. В PR временно присутствовал одноразовый workflow, предназначенный только для
   точного механического применения этих review transforms; он обязан удалить
   себя в том же review-fix commit.
6. Bootstrap environment читался до гарантированной инициализации dotenv.
7. Compatibility constructor barcode dispatcher не сохранял legacy handler.
8. Pre-auth admission не учитывал `runtimeActive`, а dispatcher мог на один async
   turn довериться устаревшему admission bit после lifecycle shutdown.
9. Logout reset не публиковал пригодный для badge auth bounded runtime/pending
   replace-to-main state.
10. Help select capability была потеряна при удалении widget-owned navigation.

Пункты 6–10 исправлены прямыми review-fix commits до этого документа. Пункты
1–5 применяются exact source transformation и повторно проверяются на новом HEAD.

Validation остаётся статической: Flutter, analyzer, Gradle, build и device tests
не запускаются.
