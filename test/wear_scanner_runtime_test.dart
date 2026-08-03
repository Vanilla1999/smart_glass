import 'package:flutter_test/flutter_test.dart';
import 'package:multi_scanner/multi_scanner.dart';
import 'package:smart_glasses/modules/wear/services/wear_scanner_runtime.dart';

void main() {
  test('scanner runtime starts and pauses idempotently', () async {
    final _FakeBaseController controller = _FakeBaseController();
    final WearScannerRuntime runtime = WearScannerRuntime(
      controller: controller,
    );

    await runtime.start();
    await runtime.start();
    await runtime.pause();
    await runtime.pause();

    expect(controller.initCalls, 1);
    expect(controller.prepareCalls, 1);
    expect(controller.pauseCalls, 1);
  });

  test('scanner runtime serializes start and final release', () async {
    final _FakeBaseController controller = _FakeBaseController();
    final WearScannerRuntime runtime = WearScannerRuntime(
      controller: controller,
    );

    final Future<void> start = runtime.start();
    final Future<void> release = runtime.release();
    await Future.wait(<Future<void>>[start, release]);

    expect(controller.calls, <String>['init', 'prepare', 'release']);
  });
}

class _FakeBaseController extends BaseController {
  int initCalls = 0;
  int prepareCalls = 0;
  int pauseCalls = 0;
  final List<String> calls = <String>[];

  @override
  Future<void> init() async {
    initCalls++;
    calls.add('init');
  }

  @override
  Future<void> prepareForWear() async {
    prepareCalls++;
    calls.add('prepare');
  }

  @override
  Future<void> pauseForWear() async {
    pauseCalls++;
    calls.add('pause');
  }

  @override
  Future<void> release() async {
    calls.add('release');
  }
}
