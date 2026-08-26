import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:multi_scanner/multi_scanner.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_control_adapter.dart';
import 'package:smart_glasses/modules/wear/services/wear_barcode_dispatcher.dart';
import 'support/wear_runtime_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('serial queue preserves barcode order', () async {
    final Completer<void> first = Completer<void>();
    final List<String> calls = <String>[];
    final WearBarcodeSerialQueue queue = WearBarcodeSerialQueue(
      handleBarcode: (String payload) async {
        calls.add(payload);
        if (payload == 'first') await first.future;
        return true;
      },
    );

    expect(queue.add('first'), isTrue);
    expect(queue.add('second'), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(calls, <String>['first']);

    first.complete();
    await queue.waitUntilIdle();
    expect(calls, <String>['first', 'second']);
  });

  test('reset keeps generations isolated without concurrent handlers',
      () async {
    final Completer<void> first = Completer<void>();
    final List<String> calls = <String>[];
    final WearBarcodeSerialQueue queue = WearBarcodeSerialQueue(
      handleBarcode: (String payload) async {
        calls.add(payload);
        if (payload == 'first') await first.future;
        return true;
      },
    );

    queue.add('first');
    queue.add('stale');
    await Future<void>.delayed(Duration.zero);
    queue.reset();
    queue.add('fresh');

    await Future<void>.delayed(Duration.zero);
    expect(calls, <String>['first']);

    first.complete();
    await queue.waitUntilIdle();
    expect(calls, <String>['first', 'fresh']);
  });

  test('waitUntilIdle includes an in-flight handler from before reset',
      () async {
    final Completer<void> first = Completer<void>();
    final WearBarcodeSerialQueue queue = WearBarcodeSerialQueue(
      handleBarcode: (String payload) async {
        await first.future;
        return true;
      },
    );
    queue.add('first');
    await Future<void>.delayed(Duration.zero);
    queue.reset();
    bool idle = false;

    final Future<void> waiting = queue.waitUntilIdle().then((_) => idle = true);
    await Future<void>.delayed(Duration.zero);
    expect(idle, isFalse);

    first.complete();
    await waiting;
    expect(idle, isTrue);
  });

  test('bounded queue reports backpressure', () async {
    final Completer<void> first = Completer<void>();
    final WearBarcodeSerialQueue queue = WearBarcodeSerialQueue(
      maxPending: 1,
      handleBarcode: (String payload) async {
        await first.future;
        return true;
      },
    );

    expect(queue.add('first'), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(queue.add('second'), isTrue);
    expect(queue.add('third'), isFalse);

    first.complete();
    await queue.waitUntilIdle();
  });

  test('does not delay or suppress immediate duplicate scans', () async {
    final List<String> calls = <String>[];
    final WearBarcodeSerialQueue queue = WearBarcodeSerialQueue(
      handleBarcode: (String payload) async {
        calls.add(payload);
        return true;
      },
    );

    expect(queue.add('9000000001'), isTrue);
    expect(queue.add('9000000001'), isTrue);
    await queue.waitUntilIdle();
    expect(calls, <String>['9000000001', '9000000001']);
  });

  test('queued delivery retains its callback captured at admission', () async {
    final Completer<void> first = Completer<void>();
    final List<String> calls = <String>[];
    final WearBarcodeSerialQueue queue = WearBarcodeSerialQueue(
      handleBarcode: (String payload) async {
        if (payload == 'first') await first.future;
        return true;
      },
    );

    queue.add('first');
    queue.addWithHandler('second', (String payload) async {
      calls.add('old-epoch:$payload');
      return false;
    });
    first.complete();

    await queue.waitUntilIdle();
    expect(calls, <String>['old-epoch:second']);
  });

  test('active phone route drift rejects delivery before semantic dispatch',
      () async {
    final authority = await createActiveWearRuntimeAuthority(
      initialScreen: WearScreenId.scanIdle,
    );
    addTearDown(authority.dispose);
    final adapter = WearRuntimeControlAdapter(authority);
    await authority
        .navigationAdapter()
        .observePhoneRoute(WearScreenId.scanIdle);
    await adapter.observeScannerPreparing();
    await adapter.observeScannerPrepared();
    await adapter.evaluateScannerAdmission(
      logicalScreen: WearScreenId.scanIdle,
      screenAcceptsBarcode: true,
    );
    expect(authority.controls.scanner.barcodeAdmissionEnabled, isTrue);

    await authority.navigationAdapter().observePhoneRoute(WearScreenId.help);
    final dispatcher = WearBarcodeDispatcher(
      authority: authority,
      scanner: MultiScanner.broadcaster(),
    )..start();
    addTearDown(dispatcher.stop);

    expect(dispatcher.onScanEvent('4600000000000'), isTrue);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(authority.controls.scanner.lastAcceptedDeliveryId, isNull);
  });
}
