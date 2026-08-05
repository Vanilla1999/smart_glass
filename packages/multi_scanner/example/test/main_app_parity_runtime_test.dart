import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:multi_scanner_example/main_app_parity_runtime.dart';

void main() {
  test(
    'starts the second engine before concurrent scanner and voice',
    () async {
      final Completer<void> scannerGate = Completer<void>();
      final List<String> events = <String>[];
      final MainAppParityRuntime runtime = MainAppParityRuntime(
        startScanner: () async {
          events.add('scanner-start');
          await scannerGate.future;
          events.add('scanner-done');
        },
        startVoice: () async {
          events.add('voice-start');
          return 'capturing';
        },
        showGlassesDisplay: () async {
          events.add('display-start');
          events.add('display-done');
          return true;
        },
        getFlashlightState: () async => 0,
        setFlashlight: (_) async {},
      );

      final Future<MainAppParityStartReport> starting = runtime.start();
      await Future<void>.delayed(Duration.zero);

      expect(events, <String>[
        'display-start',
        'display-done',
        'scanner-start',
        'voice-start',
      ]);
      expect(events, isNot(contains('scanner-done')));

      scannerGate.complete();
      final MainAppParityStartReport report = await starting;
      expect(report.voiceStatus, 'capturing');
      expect(report.displayShown, isTrue);
    },
  );

  test('toggle uses tracked state after the first hardware read', () async {
    final List<int> requested = <int>[];
    final List<int> reads = <int>[0, 1, 0, 0];
    final MainAppParityRuntime runtime = MainAppParityRuntime(
      startScanner: () async {},
      startVoice: () async => 'capturing',
      showGlassesDisplay: () async => true,
      getFlashlightState: () async => reads.removeAt(0),
      setFlashlight: (int state) async => requested.add(state),
      delay: (_) async {},
    );

    final FlashlightParityProbe first = await runtime
        .toggleFlashlightLikeMain();
    final FlashlightParityProbe second = await runtime
        .toggleFlashlightLikeMain();

    expect(first.requested, 1);
    expect(first.stateAcknowledged, isTrue);
    expect(
      second.observedBefore,
      0,
      reason: 'hardware read is intentionally stale',
    );
    expect(second.logicalBefore, 1, reason: 'production prefers tracked state');
    expect(second.requested, 0);
    expect(requested, <int>[1, 0]);
  });

  test('read-after-write mismatch remains visible in the probe', () async {
    var reads = 0;
    final MainAppParityRuntime runtime = MainAppParityRuntime(
      startScanner: () async {},
      startVoice: () async => 'capturing',
      showGlassesDisplay: () async => true,
      getFlashlightState: () async {
        reads++;
        return 0;
      },
      setFlashlight: (_) async {},
      delay: (_) async {},
      nativeDiagnostics: () async => <String, dynamic>{'engines': 2},
    );

    final FlashlightParityProbe probe = await runtime
        .toggleFlashlightLikeMain();

    expect(probe.requested, 1);
    expect(probe.observedAfter, 0);
    expect(probe.stateAcknowledged, isFalse);
    expect(probe.verificationAttempts, 5);
    expect(reads, 6); // one pre-read plus five verification reads
    expect(probe.diagnostics['engines'], 2);
  });

  test('failed start can be retried', () async {
    var attempts = 0;
    final MainAppParityRuntime runtime = MainAppParityRuntime(
      startScanner: () async {
        attempts++;
        if (attempts == 1) throw StateError('first start failed');
      },
      startVoice: () async => 'capturing',
      showGlassesDisplay: () async => true,
      getFlashlightState: () async => 0,
      setFlashlight: (_) async {},
    );

    await expectLater(runtime.start(), throwsA(isA<MainAppParityException>()));
    expect((await runtime.start()).voiceStatus, 'capturing');
    expect(attempts, 2);
  });
}
