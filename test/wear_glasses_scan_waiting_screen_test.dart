import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/wear/wear_glasses_cubit.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/wear/wear_scan_overlay_cubit.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/wear/wear_voice_overlay_cubit.dart';
import 'package:smart_glasses/features/glasses/presentation/screens/wear/wear_glasses_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

void main() {
  testWidgets('scan waiting shows only the prompt and barcode reticle',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(640, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final WearGlassesCubit glassesCubit = WearGlassesCubit()
      ..updateFromPayload(WearGlassesPayload.scanWaiting().toJson());
    final WearScanOverlayCubit scanOverlayCubit = WearScanOverlayCubit()
      ..update(<String, dynamic>{
        'visible': true,
        'revision': 1,
        'phase': 'searching',
      });
    final WearVoiceOverlayCubit voiceOverlayCubit = WearVoiceOverlayCubit();
    addTearDown(glassesCubit.close);
    addTearDown(scanOverlayCubit.close);
    addTearDown(voiceOverlayCubit.close);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: <BlocProvider<dynamic>>[
          BlocProvider<WearGlassesCubit>.value(value: glassesCubit),
          BlocProvider<WearScanOverlayCubit>.value(value: scanOverlayCubit),
          BlocProvider<WearVoiceOverlayCubit>.value(value: voiceOverlayCubit),
        ],
        child: const MaterialApp(home: WearGlassesScreen()),
      ),
    );

    final Finder prompt = find.text('Наведите камеру на штрих-код');
    expect(prompt, findsOneWidget);
    expect(find.text('Сканирование'), findsNothing);
    expect(find.text('Поиск ШК...'), findsNothing);
    expect(find.byKey(const Key('wear-scan-reticle')), findsOneWidget);
    expect(tester.widget<Text>(prompt).style?.fontSize, 20);
  });

  testWidgets('scan loading hides the barcode reticle',
      (WidgetTester tester) async {
    final WearGlassesCubit glassesCubit = WearGlassesCubit()
      ..updateFromPayload(WearGlassesPayload.scanLoading().toJson());
    final WearScanOverlayCubit scanOverlayCubit = WearScanOverlayCubit()
      ..update(<String, dynamic>{
        'visible': true,
        'revision': 1,
        'phase': 'locked',
        'left': 0.4,
        'right': 0.6,
        'top': 0.4,
        'bottom': 0.6,
      });
    final WearVoiceOverlayCubit voiceOverlayCubit = WearVoiceOverlayCubit();
    addTearDown(glassesCubit.close);
    addTearDown(scanOverlayCubit.close);
    addTearDown(voiceOverlayCubit.close);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: <BlocProvider<dynamic>>[
          BlocProvider<WearGlassesCubit>.value(value: glassesCubit),
          BlocProvider<WearScanOverlayCubit>.value(value: scanOverlayCubit),
          BlocProvider<WearVoiceOverlayCubit>.value(value: voiceOverlayCubit),
        ],
        child: const MaterialApp(home: WearGlassesScreen()),
      ),
    );

    expect(find.byKey(const Key('wear-scan-reticle')), findsNothing);
  });
}
