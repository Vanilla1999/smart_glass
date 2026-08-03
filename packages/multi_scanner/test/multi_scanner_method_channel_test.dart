import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_scanner/src/platform/multi_scanner_method_channel.dart';

void main() {
  MethodChannelMultiScanner platform = MethodChannelMultiScanner();
  const MethodChannel channel =
      MethodChannel('tander/multi_scanner_plugin/channel');

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
    expect(
      calls.single.arguments,
      {'uri': 'content://photo-provider/glasses/photo.jpg'},
    );
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
}
