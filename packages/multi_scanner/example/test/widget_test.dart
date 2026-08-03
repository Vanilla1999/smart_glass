// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_scanner/multi_scanner.dart';

import 'package:multi_scanner_example/main.dart';

void main() {
  testWidgets('toggles Movfast flashlight state', (WidgetTester tester) async {
    if (!getIt.isRegistered<MultiScanner>()) {
      getIt.registerSingleton<MultiScanner>(MultiScanner.last());
    }

    var flashlightState = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('tander/multi_scanner_plugin/channel'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'setFlashlight') {
          flashlightState = methodCall.arguments['state'];
          return null;
        }
        if (methodCall.method == 'getFlashlightState') {
          return flashlightState;
        }
        if (methodCall.method == 'isPCH' ||
            methodCall.method == 'isDefaultHorizontal' ||
            methodCall.method == 'isNotNeedCamera' ||
            methodCall.method == 'isNeedBT') {
          return false;
        }
        return null;
      },
    );

    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    expect(find.text('Flashlight state: 0'), findsOneWidget);

    await tester.tap(find.text('toggleFlashlight'));
    await tester.pump();

    expect(find.text('Flashlight state: 1'), findsOneWidget);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('tander/multi_scanner_plugin/channel'),
      null,
    );
  });
}
