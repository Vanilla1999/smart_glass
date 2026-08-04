import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/services/wear_barcode_dispatcher.dart';

void main() {
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

  test('reset drops old pending scans but accepts a new generation', () async {
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
    first.complete();

    await queue.waitUntilIdle();
    expect(calls, <String>['first', 'fresh']);
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
}
