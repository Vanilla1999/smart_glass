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
        'Последнее фото',
        'Печать ценников',
        'Доступность',
        'Справка',
        'Настройки',
      ],
    );
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
