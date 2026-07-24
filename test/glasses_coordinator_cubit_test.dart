import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/app/glasses/glasses_coordinator_cubit.dart';
import 'package:smart_glasses/app/glasses/glasses_coordinator_state.dart';
import 'package:smart_glasses/core/constants/app_constants.dart';
import 'package:smart_glasses/core/services/method_channel_service.dart';

Future<void> simulateIncomingMethodCall(
  MethodChannel channel,
  MethodCall call,
) {
  final ByteData encoded = channel.codec.encodeMethodCall(call);
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(channel.name, encoded, (ByteData? data) {});
}

void main() {
  group('GlassesCoordinatorCubit', () {
    late MethodChannel channel;
    String? lastNavigatedRoute;
    bool homeCalled = false;
    int lastCounter = 0;
    String lastScreen1Text = '';
    String lastScreen2Text = '';
    Map<String, dynamic>? lastWearPayload;
    Map<String, dynamic>? lastVoiceOverlay;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();

      channel = MethodChannel(AppConstants.glassesChannelName);
      lastNavigatedRoute = null;
      homeCalled = false;
      lastCounter = 0;
      lastScreen1Text = '';
      lastScreen2Text = '';
      lastWearPayload = null;
      lastVoiceOverlay = null;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async {
          if (methodCall.method == 'getInitialCounter') {
            return 42;
          }
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    GlassesCoordinatorCubit createCubit() {
      return GlassesCoordinatorCubit(
        methodChannelService: MethodChannelService(),
        onNavigateToScreen: (String route) {
          lastNavigatedRoute = route;
        },
        onNavigateHome: () {
          homeCalled = true;
        },
        onUpdateScreen1Counter: (int counter) {
          lastCounter = counter;
        },
        onUpdateScreen1RecognizedText: (String text) {
          lastScreen1Text = text;
        },
        onUpdateScreen2RecognizedText: (String text) {
          lastScreen2Text = text;
        },
        onUpdateWearGlasses: (Map<String, dynamic> payload) {
          lastWearPayload = payload;
        },
        onUpdateWearVoiceOverlay: (Map<String, dynamic> payload) {
          lastVoiceOverlay = payload;
        },
      );
    }

    test('initial state is GlassesCoordinatorInitial', () {
      final GlassesCoordinatorCubit cubit = createCubit();
      addTearDown(cubit.close);

      expect(cubit.state, isA<GlassesCoordinatorInitial>());
    });

    test('init calls getInitialCounter and emits Ready', () async {
      final GlassesCoordinatorCubit cubit = createCubit();
      addTearDown(cubit.close);

      await cubit.init();

      expect(
        cubit.state,
        isA<GlassesCoordinatorReady>().having(
          (s) => s.currentRoute,
          'currentRoute',
          '/',
        ),
      );
      expect(lastCounter, 42);
    });

    test('navigateToRoute "/" calls onNavigateHome', () async {
      final GlassesCoordinatorCubit cubit = createCubit();
      addTearDown(cubit.close);

      await cubit.init();
      await simulateIncomingMethodCall(
        channel,
        MethodCall('navigateToRoute', '/'),
      );

      expect(homeCalled, isTrue);
      expect(lastNavigatedRoute, isNull);
      expect(
        cubit.state,
        isA<GlassesCoordinatorReady>().having(
          (s) => s.currentRoute,
          'currentRoute',
          '/',
        ),
      );
    });

    test('navigateToRoute "/screen2" calls onNavigateToScreen', () async {
      final GlassesCoordinatorCubit cubit = createCubit();
      addTearDown(cubit.close);

      await cubit.init();
      await simulateIncomingMethodCall(
        channel,
        MethodCall('navigateToRoute', '/screen2'),
      );

      expect(lastNavigatedRoute, '/screen2');
      expect(homeCalled, isFalse);
      expect(
        cubit.state,
        isA<GlassesCoordinatorReady>().having(
          (s) => s.currentRoute,
          'currentRoute',
          '/screen2',
        ),
      );
    });

    test('navigateToScreen with route map calls onNavigateToScreen', () async {
      final GlassesCoordinatorCubit cubit = createCubit();
      addTearDown(cubit.close);

      await cubit.init();
      await simulateIncomingMethodCall(
        channel,
        MethodCall(
          'navigateToScreen',
          <String, dynamic>{'route': '/screen2'},
        ),
      );

      expect(lastNavigatedRoute, '/screen2');
    });

    test('updateWearGlasses forwards map payload to callback', () async {
      final GlassesCoordinatorCubit cubit = createCubit();
      addTearDown(cubit.close);

      await cubit.init();
      final Map<String, dynamic> payload = <String, dynamic>{
        'screenType': 'menu',
        'selectedIndex': 2,
      };
      await simulateIncomingMethodCall(
        channel,
        MethodCall('updateWearGlasses', payload),
      );

      expect(lastWearPayload, payload);
    });

    test('updateWearVoiceOverlay forwards map payload to callback', () async {
      final GlassesCoordinatorCubit cubit = createCubit();
      addTearDown(cubit.close);

      await cubit.init();
      final Map<String, dynamic> payload = <String, dynamic>{
        'visible': true,
        'message': 'Переподключаем голосовое управление',
      };
      await simulateIncomingMethodCall(
        channel,
        MethodCall('updateWearVoiceOverlay', payload),
      );

      expect(lastVoiceOverlay, payload);
    });

    test('recognized text routes to screen1 on default route', () async {
      final GlassesCoordinatorCubit cubit = createCubit();
      addTearDown(cubit.close);

      await cubit.init();
      await simulateIncomingMethodCall(
        channel,
        MethodCall('updateRecognizedText', 'привет'),
      );

      expect(lastScreen1Text, 'привет');
      expect(lastScreen2Text, isEmpty);
    });

    test('recognized text routes to screen2 when on screen2 route', () async {
      final GlassesCoordinatorCubit cubit = createCubit();
      addTearDown(cubit.close);

      await cubit.init();
      await simulateIncomingMethodCall(
        channel,
        MethodCall('navigateToRoute', '/screen2'),
      );
      await simulateIncomingMethodCall(
        channel,
        MethodCall('updateRecognizedText', 'текст для второго'),
      );

      expect(lastScreen2Text, 'текст для второго');
      expect(lastScreen1Text, isEmpty);
    });

    test('updateCounter routes to screen1 callback', () async {
      lastCounter = 0;
      final GlassesCoordinatorCubit cubit = createCubit();
      addTearDown(cubit.close);

      await cubit.init();
      await simulateIncomingMethodCall(
        channel,
        MethodCall('updateCounter', 99),
      );

      expect(lastCounter, 99);
    });
  });
}
