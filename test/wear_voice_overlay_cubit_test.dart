import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/wear/wear_voice_overlay_cubit.dart';

void main() {
  test('voice overlay state is independent from wear screen payloads', () {
    final WearVoiceOverlayCubit cubit = WearVoiceOverlayCubit();
    addTearDown(cubit.close);

    cubit.update(<String, dynamic>{
      'visible': true,
      'revision': 1,
      'phase': 'reconnecting',
      'reason': 'resume',
      'attempt': 1,
      'message': 'Переподключаем\nголосовое управление',
    });

    expect(cubit.state.visible, isTrue);
    expect(cubit.state.message, 'Переподключаем\nголосовое управление');
    expect(cubit.state.isError, isFalse);

    cubit.update(<String, dynamic>{
      'visible': true,
      'revision': 2,
      'phase': 'unavailable',
      'message': 'Голосовое управление недоступно',
    });

    expect(cubit.state.isError, isTrue);

    cubit.update(<String, dynamic>{
      'visible': false,
      'revision': 1,
      'phase': 'preparing',
    });

    expect(cubit.state.visible, isTrue);
    expect(cubit.state.revision, 2);

    cubit.update(<String, dynamic>{
      'visible': false,
      'revision': 2,
      'phase': 'preparing',
    });

    expect(cubit.state.visible, isTrue);
    expect(cubit.state.revision, 2);
  });
}
