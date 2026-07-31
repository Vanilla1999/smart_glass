import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/wear/wear_glasses_cubit.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

void main() {
  test('updates glasses state from payload map', () {
    final WearGlassesCubit cubit = WearGlassesCubit();
    addTearDown(cubit.close);

    cubit.updateFromPayload(WearGlassesPayload.menu().toJson());

    expect(cubit.state.screenType, WearGlassesScreenType.menu);
    expect(cubit.state.phase, WearGlassesPhase.idle);
    expect(cubit.state.title, 'Выбор раздела');
    expect(
      cubit.state.items,
      <String>[
        'Печать ценников',
        'Доступность',
        'Справка',
        'Настройки',
      ],
    );
    expect(cubit.state.updateId, 1);
    expect(cubit.state.payloadReceivedAtMillis, greaterThan(0));
  });

  test('assigns a unique id to each glasses update', () {
    final WearGlassesCubit cubit = WearGlassesCubit();
    addTearDown(cubit.close);

    cubit.updateFromPayload(WearGlassesPayload.menu().toJson());
    cubit.updateFromPayload(
      WearGlassesPayload.menu(selectedIndex: 1).toJson(),
    );

    expect(cubit.state.updateId, 2);
    expect(cubit.state.selectedIndex, 1);
  });

  test('parses performance trace for frame latency logging', () {
    final WearGlassesCubit cubit = WearGlassesCubit();
    addTearDown(cubit.close);

    cubit.updateFromPayload(
      WearGlassesPayload.menu()
          .copyWithPerformanceTrace(
            traceId: '7:3:1',
            command: 'up',
            recognizedAtMillis: 1000,
            asrMillis: 125,
            sentAtMillis: 1040,
          )
          .toJson(),
    );

    expect(cubit.state.performanceTraceId, '7:3:1');
    expect(cubit.state.performanceCommand, 'up');
    expect(cubit.state.performanceRecognizedAtMillis, 1000);
    expect(cubit.state.performanceAsrMillis, 125);
    expect(cubit.state.performanceSentAtMillis, 1040);
  });

  test('retains structured voice hints', () {
    final WearGlassesCubit cubit = WearGlassesCubit();
    addTearDown(cubit.close);

    cubit.updateFromPayload(const WearGlassesPayload(
      screenType: WearGlassesScreenType.printer,
      phase: WearGlassesPhase.idle,
      title: 'Принтеры',
      items: <String>['MOCK Белый 1'],
      voiceHints: <WearGlassesVoiceHint>[
        WearGlassesVoiceHint(
          itemId: 'printer-1',
          phrase: 'белый',
          start: 5,
          end: 10,
        ),
      ],
    ).toJson());

    expect(cubit.state.voiceHints, hasLength(1));
    expect(cubit.state.voiceHints.single.phrase, 'белый');
    expect(cubit.state.voiceHints.single.isValidFor('MOCK Белый 1'), isTrue);
  });

  test('maps item maps to titles defensively', () {
    final WearGlassesCubit cubit = WearGlassesCubit();
    addTearDown(cubit.close);

    cubit.updateFromPayload(<String, dynamic>{
      'screenType': 'printer',
      'phase': 'idle',
      'title': 'Выбор принтера',
      'items': <Map<String, dynamic>>[
        <String, dynamic>{'title': 'Printer 1'},
      ],
    });

    expect(cubit.state.screenType, WearGlassesScreenType.printer);
    expect(cubit.state.items, <String>['Printer 1']);
  });

  test('parses partial and loosely typed payload defensively', () {
    final WearGlassesCubit cubit = WearGlassesCubit();
    addTearDown(cubit.close);

    cubit.updateFromPayload(<String, dynamic>{
      'screenType': 'scan',
      'phase': 'loading',
      'title': 123,
      'subtitle': null,
      'isLoading': 'true',
      'isError': 0,
      'selectedIndex': 2.7,
      'items': <Object?>[
        'First',
        <String, dynamic>{'title': 'Second'},
        null,
      ],
    });

    expect(cubit.state.screenType, WearGlassesScreenType.scan);
    expect(cubit.state.phase, WearGlassesPhase.loading);
    expect(cubit.state.title, '123');
    expect(cubit.state.subtitle, isNull);
    expect(cubit.state.isLoading, isTrue);
    expect(cubit.state.isError, isFalse);
    expect(cubit.state.selectedIndex, 2);
    expect(cubit.state.items, <String>['First', 'Second', 'null']);
  });
}
