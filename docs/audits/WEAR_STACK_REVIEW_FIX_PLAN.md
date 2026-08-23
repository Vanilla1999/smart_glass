# Wear stack review findings: fix plan

Дата: 2026-08-23.

## 1. Контекст

- Base branch: `experiment/aligned-audio-frontend`.
- Base commit: `5b203450eff51119d65cd0c4f3817b2d4a0fc38e`.
- Fix branch: `fix/wear-stack-review-findings`.
- Цель: отдельным bounded MR исправить доказанные замечания финального review
  merge stack, не смешивая их с новой большой миграцией presentation layer.

## 2. Scope

### 2.1. Контракт успешной печати

1. Переименовать результат `WearPriceTagPrintSucceeded` из `productName` в
   `printerName`, потому что production `PrintPriceTagUseCase` возвращает имя
   принтера.
2. Сохранить уже выбранное имя товара в `WearScanTaskSlice.productName`.
3. Формировать success status так:
   - `message` — имя товара;
   - `details` — имя принтера.
4. Исправить основной scan reducer и status-sequencing reducer одинаково.
5. Исправить mock path, чтобы его контракт совпадал с production path.

### 2.2. Регрессионные тесты

Добавить/обновить тесты с различающими значениями, например:

- товар: `Молоко`;
- принтер: `Белый принтер`.

Проверить на уровне reducer/state contract:

- `scan.productName` остаётся `Молоко`;
- status `message` содержит `Молоко`;
- status `details` содержит `Белый принтер`;
- sequencing reducer формирует тот же результат;
- effect executor возвращает `printerName`, а не маскирует его как товар.

### 2.3. Merge report и evidence

1. Разделить:
   - stack merge baseline: `10d639b25a7be567fbafc3f9ef0c972040c670ec`;
   - post-merge stabilization/base reviewed HEAD:
     `5b203450eff51119d65cd0c4f3817b2d4a0fc38e`.
2. Удалить устаревшие утверждения о незакоммиченных production fixes.
3. Не выдавать локальный test/analyzer/APK результат за commit-bound CI evidence:
   явно записать, что это сохранённый локальный snapshot без повторного запуска в
   этом MR.
4. Честно обозначить оставшийся compatibility layer `WearFlowController` и
   adapters: aggregate slices являются authoritative owners мигрированных
   business values, но полный presentation cleanup исходного Definition of Done
   остаётся follow-up работой.
5. Сохранить device-only проверки как обязательные release gates.

## 3. Не входит в MR

- Полное удаление `WearFlowController` и всех compatibility adapters.
- Переписывание всех phone widgets на новую projection API.
- Новые изменения voice/UAC4/audio transport.
- Запуск `flutter`, `dart analyze`, Gradle или Android build.
- Hardware/device validation.

Эти пункты нельзя маскировать формулировкой «выполнено»; они должны быть явно
отражены как follow-up/release gates.

## 4. Порядок реализации

1. Обновить typed print-success intent и effect executor.
2. Обновить оба reducer.
3. Мигрировать все compile-time references в тестах.
4. Добавить различающие contract assertions.
5. Обновить merge report и документационный индекс при необходимости.
6. Открыть PR в `experiment/aligned-audio-frontend`.
7. Выполнить review только по diff и связанным контрактам, без запуска Flutter и
   Gradle.
8. Исправить все найденные в review замечания и повторно проверить diff.

## 5. Acceptance criteria

- В diff нет использования `WearPriceTagPrintSucceeded.productName`.
- Production и mock print paths возвращают одинаковую семантику: имя принтера.
- Success status не перезаписывает имя товара именем принтера.
- Тесты используют разные строки товара и принтера.
- Merge report соответствует remote commit history и не утверждает больше, чем
  подтверждено.
- PR не содержит audio, generated artifacts, build outputs или unrelated cleanup.
