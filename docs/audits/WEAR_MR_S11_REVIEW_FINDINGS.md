# MR-S11 static review findings

Дата: 2026-08-24.

PR: [#16](https://github.com/Vanilla1999/smart_glass/pull/16).

Первый exact-head review на
`4afebb0eac50ca4311c9afe18821889d00d55075` подтвердил направление MR-S11,
но поставил `REQUEST CHANGES` из-за следующих blocking gaps:

1. `WearVoiceApplicationDispatcher` определял screen через
   `_flow.state.screen`, а не committed aggregate navigation.
2. Scanner capability входил в legacy registry без fail-closed проверки
   расхождения aggregate/compatibility screen.
3. `WearMainScreen.initState()` мог инициировать logical menu navigation после
   widget attachment.
4. Unsupported barcode fallback не был явно ограничен anonymous `main`.
5. Source gates не покрывали voice dispatcher, stale mirror, auth lifecycle и
   fallback boundary.

Дополнительный review call graph выявил post-logout риск: compatibility cleanup
должен сохранять aggregate transition на `main`, иначе bounded pre-auth path
мог бы закрыться после session reset.

## Исправления

- `92f83672bd423d4048706aabbf10ce63ef1f66e4` — voice preview, delay,
  context и logging переведены на aggregate `logicalScreen`;
- `2927d5152409b54321cfe8ea83eb8a589a4d4d0a` — auth widget attachment
  перестал инициировать logical navigation;
- `2e9e485451bffe4f29653e5ef20ee8578673af65` — barcode fallback
  ограничен `!authorized && logicalScreen == main`;
- `60e3d48eece192f98512ee1e5b5849dd2206590e` — production facade
  fail-closed отклоняет barcode/voice/button при stale compatibility mirror;
- `62327b97c0a3dceb8ed94132779e1a8d496608d4` — добавлены source-level
  regression gates;
- `c8da9bea0b90e3cd824f086db35173c1eef82230` — session reset явно
  выравнивает retained mirror с aggregate logical screen;
- `920ee0cb4d58318e8cf454b3d93030969839ae0b` — временный механический
  workflow удалён и не входит в финальный diff.

До этих commits в ветке также были закрыты bootstrap dotenv, compatibility
constructor, runtime-active pre-auth admission, logout pending replace-to-main и
help-select regressions. Они повторно проверены в полном final diff.

## Итог повторного review

- external business-screen attribution идёт из одного aggregate snapshot;
- actual Flutter route является только epoch-bound observation;
- widget attachment не запускает business entry;
- barcode delivery сохраняет captured epoch/screen;
- stale controller mirror не может исполнить callback на другом screen;
- anonymous fallback существует только для badge auth на `main`;
- физический `WearFlowState`/status/clarification cleanup честно остаётся MR-S12.

Validation остаётся статической: Flutter, analyzer, Gradle, build и device tests
не запускались.
