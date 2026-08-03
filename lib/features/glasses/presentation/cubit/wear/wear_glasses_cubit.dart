import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/wear/wear_glasses_state.dart';

class WearGlassesCubit extends Cubit<WearGlassesState> {
  WearGlassesCubit() : super(WearGlassesState.initial());

  int _updateId = 0;

  void updateFromPayload(Map<String, dynamic> payload) {
    final int receivedAtMillis = DateTime.now().millisecondsSinceEpoch;
    final WearGlassesState next = WearGlassesState.fromPayload(
      payload,
      updateId: ++_updateId,
      payloadReceivedAtMillis: receivedAtMillis,
    );
    emit(next);
  }
}
