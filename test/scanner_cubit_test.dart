import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:multi_scanner/multi_scanner.dart';
import 'package:smart_glasses/features/scanner/presentation/cubit/scanner_cubit.dart';
import 'package:smart_glasses/features/scanner/presentation/cubit/scanner_state.dart';

void main() {
  test('initialization waits for recommended scanner settings', () async {
    final _FakeBaseController controller = _FakeBaseController();
    final ScannerCubit cubit = ScannerCubit(
      controller: controller,
      scanner: _FakeMultiScanner(),
    );
    addTearDown(cubit.close);

    var completed = false;
    final Future<void> initialization = cubit.init().then((_) {
      completed = true;
    });
    await Future<void>.delayed(Duration.zero);

    expect(controller.initCalls, 1);
    expect(controller.settingsCalls, 1);
    expect(completed, isFalse);
    expect(cubit.state, isA<ScannerConnecting>());

    controller.settings.complete();
    await initialization;
    expect(completed, isTrue);
  });

  test('close during initialization prevents a late subscription', () async {
    final Completer<void> initialization = Completer<void>();
    final _FakeBaseController controller = _FakeBaseController(
      initialization: initialization,
    );
    final _FakeMultiScanner scanner = _FakeMultiScanner();
    final ScannerCubit cubit = ScannerCubit(
      controller: controller,
      scanner: scanner,
    );

    final Future<void> pending = cubit.init();
    await Future<void>.delayed(Duration.zero);
    await cubit.close();
    initialization.complete();
    await pending;

    expect(scanner.delegates, isEmpty);
    expect(controller.settingsCalls, 0);
    expect(controller.connections.hasListener, isFalse);
  });

  test('parallel init calls share one initialization', () async {
    final _FakeBaseController controller = _FakeBaseController();
    final _FakeMultiScanner scanner = _FakeMultiScanner();
    final ScannerCubit cubit = ScannerCubit(
      controller: controller,
      scanner: scanner,
    );
    addTearDown(cubit.close);

    final Future<void> first = cubit.init();
    final Future<void> second = cubit.init();
    await Future<void>.delayed(Duration.zero);
    controller.settings.complete();
    await Future.wait(<Future<void>>[first, second]);

    expect(controller.initCalls, 1);
    expect(controller.settingsCalls, 1);
    expect(scanner.delegates, <MultiScannerDelegate>[cubit]);
  });

  test('failed initialization can be retried', () async {
    final _RetryBaseController controller = _RetryBaseController();
    final _FakeMultiScanner scanner = _FakeMultiScanner();
    final ScannerCubit cubit = ScannerCubit(
      controller: controller,
      scanner: scanner,
    );
    addTearDown(cubit.close);

    await cubit.init();
    expect(cubit.state, isA<ScannerError>());
    await cubit.init();

    expect(controller.initCalls, 2);
    expect(controller.settingsCalls, 1);
    expect(scanner.delegates, <MultiScannerDelegate>[cubit]);
  });

  test('parallel close calls share one future', () async {
    final ScannerCubit cubit = ScannerCubit(scanner: _FakeMultiScanner());

    final Future<void> first = cubit.close();
    final Future<void> second = cubit.close();

    expect(identical(first, second), isTrue);
    await first;
  });
}

class _RetryBaseController extends BaseController {
  int initCalls = 0;
  int settingsCalls = 0;

  @override
  Future<void> init() async {
    initCalls++;
    if (initCalls == 1) throw StateError('init failed');
  }

  @override
  Future<void> setRecomendedSettings() async => settingsCalls++;

  @override
  Stream<bool> get isServiceConnected => const Stream<bool>.empty();
}

class _FakeBaseController extends BaseController {
  _FakeBaseController({Completer<void>? initialization})
      : initialization = initialization ?? Completer<void>() {
    if (initialization == null) this.initialization.complete();
  }

  final Completer<void> initialization;
  final Completer<void> settings = Completer<void>();
  final StreamController<bool> connections = StreamController<bool>.broadcast();
  int initCalls = 0;
  int settingsCalls = 0;

  @override
  Future<void> init() async {
    initCalls++;
    await initialization.future;
  }

  @override
  Future<void> setRecomendedSettings() {
    settingsCalls++;
    return settings.future;
  }

  @override
  Stream<bool> get isServiceConnected => connections.stream;
}

class _FakeMultiScanner implements MultiScanner {
  final List<MultiScannerDelegate> delegates = <MultiScannerDelegate>[];

  @override
  bool active = true;

  @override
  void addDelegate(MultiScannerDelegate delegate) => delegates.add(delegate);

  @override
  void removeDelegate(MultiScannerDelegate delegate) =>
      delegates.remove(delegate);

  @override
  void removeAllDelegate() => delegates.clear();

  @override
  void receiveBarcode(String barcode) {
    for (final MultiScannerDelegate delegate in delegates) {
      delegate.onScanEvent(barcode);
    }
  }

  @override
  void off() => active = false;

  @override
  void on() => active = true;

  @override
  MultiScannerSubscription subscribe(
    PdtEventCallback onEvent, [
    PdtErrorCallback? onError,
  ]) {
    throw UnimplementedError();
  }
}
