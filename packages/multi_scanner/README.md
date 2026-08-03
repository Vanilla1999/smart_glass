# multi_scanner

Flutter-плагин для работы со встроенными и Bluetooth-сканерами на Android.
Поддерживаются Honeywell 50k и Urovo DT40.

## Требования

- Android-приложение.
- Dart SDK `>=3.10.0 <4.0.0` и Flutter `>=3.38.7`.
- Для Honeywell разрешение `com.honeywell.decode.permission.DECODE` добавляется плагином автоматически.

## Подключение

Добавьте зависимость в `pubspec.yaml` приложения:

```yaml
dependencies:
  multi_scanner:
    git:
      url: https://coderepo.corp.tander.ru/inner-enterprise-projects/android/multiscanner.git
      # ref: <tag-or-commit> # рекомендуется закрепить версию
```

Затем выполните `flutter pub get` и импортируйте API:

```dart
import 'package:multi_scanner/multi_scanner.dart';
```

## Инициализация и сканирование

Инициализируйте сервис один раз при запуске экрана или приложения. Получение штрихкодов удобно подключать через `MultiScannerDelegate`:

```dart
class ScannerController implements MultiScannerDelegate {
  ScannerController()
      : scanner = MultiScanner.last();

  final BaseController baseController = BaseController();
  final MultiScanner scanner;

  Future<void> start() async {
    scanner.addDelegate(this);
    await baseController.init();
    await baseController.setRecomendedSettings();
  }

  @override
  bool? onScanEvent(String barcode) {
    // Передайте штрихкод в состояние или бизнес-логику.
    return true;
  }

  @override
  bool? onErrorScan(Exception error) {
    // Обработайте ошибку сканирования.
    return true;
  }

  Future<void> dispose() async {
    scanner.removeDelegate(this);
    await baseController.release();
  }
}
```

`MultiScanner.last()` отправляет результат последнему добавленному delegate. Если результат должны получать все подписчики, используйте `MultiScanner.broadcaster()`.

## Контроль подключения сервиса

Подключение к сервису сканера - это не то же самое, что включённость сканера. Для него используйте `BaseController`:

- `await baseController.isConnected` возвращает актуальное состояние одним запросом.
- `baseController.isServiceConnected` сообщает последующие изменения состояния: `true` - сервис подключён, `false` - отключён.
- `scannerDisabled` отдельно сообщает, отключён ли сканер через `disableScanner()`; это не индикатор доступности сервиса.

Подпишитесь на поток **до** `init()`, чтобы не пропустить событие инициализации, а после инициализации запросите снимок текущего состояния. Поток не воспроизводит последнее значение для новых подписчиков.

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:multi_scanner/multi_scanner.dart';

class _ScannerScreenState extends State<ScannerScreen> {
  final BaseController _baseController = BaseController();
  StreamSubscription<bool>? _connectionSubscription;
  bool _serviceConnected = false;

  @override
  void initState() {
    super.initState();
    _startScanner();
  }

  Future<void> _startScanner() async {
    _connectionSubscription = _baseController.isServiceConnected.listen(
      (isConnected) {
        if (!mounted) return;
        setState(() => _serviceConnected = isConnected);
      },
      onError: (Object error, StackTrace stackTrace) {
        // Запишите ошибку в ваш логгер.
      },
    );

    await _baseController.init();
    final isConnected = await _baseController.isConnected;
    if (mounted) {
      setState(() => _serviceConnected = isConnected);
    }
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    // Вызывайте release(), только если этот экран владеет жизненным циклом сервиса.
    _baseController.release();
    super.dispose();
  }
}
```

Например, в UI можно показать `Сканер подключён` при `_serviceConnected == true` и не разрешать начало сканирования при `false`. При отключении сервисом повторите инициализацию в соответствии с политикой приложения, а не только изменяйте индикатор.

## Bluetooth-сканер

Для Bluetooth сначала вызовите `MultiScannerBluetooth().init()`. Далее доступны:

- `startWork()` и `stopWork()` для запуска и остановки Bluetooth-работы.
- `startDiscovery()` и `cancelDiscovery()` для поиска устройств.
- `streamOnBTFound` для найденных устройств и `streamOnBTBound` для связанных устройств.
- `connect(name, address)` для подключения связанного устройства.
- `connectionStream`: объект `BTDevice` при подключении и `null` при отключении.
- `barcodeStream` для штрихкодов с Bluetooth-сканера.

В `example/lib/bluetooth_dialog_portrait_widget.dart` показаны поиск, pairing и подключение устройства. В `example/lib/first/cubit/first_screen_cubit.dart` есть минимальная подписка на `isServiceConnected`; в production-коде вместо `print` используйте подход из раздела выше с хранением состояния и отменой подписки.
