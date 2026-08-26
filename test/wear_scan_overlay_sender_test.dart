import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_scanner/multi_scanner.dart';
import 'package:multi_scanner/src/platform/multi_scanner_platform_interface.dart';
import 'package:smart_glasses/core/constants/app_constants.dart';
import 'package:smart_glasses/modules/wear/infrastructure/wear_scan_overlay_sender.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('keeps only the latest tracking payload while a send is in flight',
      () async {
    const MethodChannel channel = MethodChannel(AppConstants.appChannelName);
    final MultiScannerPlatform originalPlatform = MultiScannerPlatform.instance;
    final _FakeTrackingPlatform platform = _FakeTrackingPlatform();
    final Completer<void> firstSendStarted = Completer<void>();
    final Completer<void> releaseFirstSend = Completer<void>();
    final Completer<void> latestSendCompleted = Completer<void>();
    final List<int> sentSequences = <int>[];
    MultiScannerPlatform.instance = platform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method != 'updateWearScanOverlay') return null;
      final Map<dynamic, dynamic> payload = call.arguments as Map;
      final int? sequence = payload['sourceSequence'] as int?;
      if (sequence == null) return null;
      sentSequences.add(sequence);
      if (sequence == 1) {
        firstSendStarted.complete();
        await releaseFirstSend.future;
      }
      if (sequence == 3) latestSendCompleted.complete();
      return null;
    });
    final WearScanOverlaySender sender = WearScanOverlaySender();
    addTearDown(() async {
      await sender.dispose();
      await platform.close();
      MultiScannerPlatform.instance = originalPlatform;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await sender.setEnabled(true);
    platform.add(_event(1));
    await firstSendStarted.future;
    platform.add(_event(2));
    platform.add(_event(3));
    releaseFirstSend.complete();
    await latestSendCompleted.future;

    expect(sentSequences, <int>[1, 3]);
  });

  test('retries tracking registration after a start failure', () async {
    const MethodChannel channel = MethodChannel(AppConstants.appChannelName);
    final MultiScannerPlatform originalPlatform = MultiScannerPlatform.instance;
    final _FakeTrackingPlatform platform = _FakeTrackingPlatform()
      ..startFailures = 1;
    MultiScannerPlatform.instance = platform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    final WearScanOverlaySender sender = WearScanOverlaySender();
    addTearDown(() async {
      await sender.dispose();
      await platform.close();
      MultiScannerPlatform.instance = originalPlatform;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await expectLater(sender.setEnabled(true), throwsStateError);
    await sender.setEnabled(true);

    expect(platform.startCalls, 2);
  });
}

BarcodeTrackingEvent _event(int sequence) => BarcodeTrackingEvent(
      contractVersion: 1,
      sequence: sequence,
      candidateId: 1,
      capturedAtElapsedRealtimeNanos: sequence * 1_000_000,
      detectedAtElapsedRealtimeNanos: sequence * 1_000_000,
      phase: BarcodeTrackingPhase.candidate,
      frameWidth: 640,
      frameHeight: 480,
      rotationDegrees: 0,
      mirrored: false,
      left: 0.2,
      top: 0.3,
      right: 0.4,
      bottom: 0.5,
    );

class _FakeTrackingPlatform extends MultiScannerPlatform {
  final StreamController<BarcodeTrackingEvent> _events =
      StreamController<BarcodeTrackingEvent>.broadcast(sync: true);
  int startCalls = 0;
  int startFailures = 0;

  @override
  Stream<BarcodeTrackingEvent> get barcodeTrackingEvents => _events.stream;

  @override
  Future<void> startBarcodeTracking() async {
    startCalls++;
    if (startFailures > 0) {
      startFailures--;
      throw StateError('start failed');
    }
  }

  @override
  Future<void> stopBarcodeTracking() async {}

  void add(BarcodeTrackingEvent event) => _events.add(event);

  Future<void> close() => _events.close();
}
