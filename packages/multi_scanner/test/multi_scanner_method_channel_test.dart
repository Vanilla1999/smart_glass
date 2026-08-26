import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_scanner/src/global_multi_scanner.dart';
import 'package:multi_scanner/src/platform/multi_scanner_method_channel.dart';

void main() {
  MethodChannelMultiScanner platform = MethodChannelMultiScanner();
  const MethodChannel channel = MethodChannel(
    'tander/multi_scanner_plugin/channel',
  );

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('getPlatformVersion', () async {
    // expect(await platform.getPlatformVersion(), '42');
  });

  test('setFlashlight sends state', () async {
    final calls = <MethodCall>[];
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      calls.add(methodCall);
      return null;
    });

    await platform.setFlashlight(1);

    expect(calls.single.method, 'setFlashlight');
    expect(calls.single.arguments, {'state': 1});
  });

  test('getFlashlightState returns state', () async {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      expect(methodCall.method, 'getFlashlightState');
      return 1;
    });

    expect(await platform.getFlashlightState(), 1);
  });

  test('changeScanSound sends sound', () async {
    final calls = <MethodCall>[];
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      calls.add(methodCall);
      return null;
    });

    await platform.changeScanSound(2);

    expect(calls.single.method, 'changeScanSound');
    expect(calls.single.arguments, {'sound': 2});
  });

  test('takePhoto returns content URI', () async {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      expect(methodCall.method, 'takePhoto');
      return 'content://photo-provider/glasses/photo.jpg';
    });

    expect(
      await platform.takePhoto(),
      'content://photo-provider/glasses/photo.jpg',
    );
  });

  test('takePhoto rejects an empty URI', () async {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      expect(methodCall.method, 'takePhoto');
      return '';
    });

    expect(
      platform.takePhoto(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'EMPTY_PHOTO_URI',
        ),
      ),
    );
  });

  test('deletePhoto sends content URI', () async {
    final calls = <MethodCall>[];
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      calls.add(methodCall);
      return null;
    });

    await platform.deletePhoto('content://photo-provider/glasses/photo.jpg');

    expect(calls.single.method, 'deletePhoto');
    expect(calls.single.arguments, {
      'uri': 'content://photo-provider/glasses/photo.jpg',
    });
  });

  test('initBluetooth waits for the native call', () async {
    final nativeCall = Completer<void>();
    var completed = false;
    channel.setMockMethodCallHandler((MethodCall methodCall) {
      expect(methodCall.method, 'initBluetooth');
      return nativeCall.future;
    });

    final initialization = platform.initBluetooth().then((_) {
      completed = true;
    });
    await Future<void>.delayed(Duration.zero);

    expect(completed, isFalse);

    nativeCall.complete();
    await initialization;
    expect(completed, isTrue);
  });

  test('prepareForWear sends lifecycle call', () async {
    final calls = <MethodCall>[];
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      calls.add(methodCall);
      return null;
    });

    await platform.prepareForWear();

    expect(calls.single.method, 'prepareForWear');
  });

  test('pauseForWear sends lifecycle call', () async {
    final calls = <MethodCall>[];
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      calls.add(methodCall);
      return null;
    });

    await platform.pauseForWear();

    expect(calls.single.method, 'pauseForWear');
  });

  test('barcode tracking lifecycle calls are serialized', () async {
    final calls = <String>[];
    final start = Completer<void>();
    channel.setMockMethodCallHandler((MethodCall methodCall) {
      calls.add(methodCall.method);
      if (methodCall.method == 'startBarcodeTracking') return start.future;
      return Future<void>.value();
    });

    final Future<void> starting = platform.startBarcodeTracking();
    final Future<void> stopping = platform.stopBarcodeTracking();
    await Future<void>.delayed(Duration.zero);

    expect(calls, <String>['startBarcodeTracking']);
    start.complete();
    await Future.wait(<Future<void>>[starting, stopping]);
    expect(calls, <String>['startBarcodeTracking', 'stopBarcodeTracking']);
  });

  test('concurrent barcode listener registrations are serialized', () async {
    final _ControlledEventChannel events = _ControlledEventChannel();
    platform = MethodChannelMultiScanner()..eventChannel = events;
    final Set<GlobalMultiScannerDelegate> delegates =
        <GlobalMultiScannerDelegate>{};
    await platform.registerListenerScan(delegates);

    final Future<void> second = platform.registerListenerScan(delegates);
    final Future<void> third = platform.registerListenerScan(delegates);
    await Future<void>.delayed(Duration.zero);

    expect(events.listenCount, 1);
    expect(events.maxConcurrentCancels, 1);

    events.completeNextCancel();
    await Future<void>.delayed(Duration.zero);
    expect(events.listenCount, 2);
    expect(events.maxConcurrentCancels, 1);

    events.completeNextCancel();
    await Future.wait(<Future<void>>[second, third]);
    expect(events.listenCount, 3);
    expect(events.maxConcurrentCancels, 1);
  });
}

class _ControlledEventChannel extends EventChannel {
  _ControlledEventChannel() : super('controlled-events');

  final List<Completer<void>> _cancellations = <Completer<void>>[];
  int listenCount = 0;
  int concurrentCancels = 0;
  int maxConcurrentCancels = 0;

  @override
  Stream<dynamic> receiveBroadcastStream([dynamic arguments]) =>
      _ControlledStream(this);

  void completeNextCancel() =>
      _cancellations.firstWhere((Completer<void> value) => !value.isCompleted)
        ..complete();
}

class _ControlledStream extends Stream<dynamic> {
  _ControlledStream(this.channel);

  final _ControlledEventChannel channel;

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    channel.listenCount++;
    return _ControlledSubscription(channel);
  }
}

class _ControlledSubscription implements StreamSubscription<dynamic> {
  _ControlledSubscription(this.channel);

  final _ControlledEventChannel channel;

  @override
  Future<void> cancel() async {
    final Completer<void> cancellation = Completer<void>();
    channel._cancellations.add(cancellation);
    channel.concurrentCancels++;
    if (channel.concurrentCancels > channel.maxConcurrentCancels) {
      channel.maxConcurrentCancels = channel.concurrentCancels;
    }
    await cancellation.future;
    channel.concurrentCancels--;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
