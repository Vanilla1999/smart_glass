import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/wear/wear_glasses_state.dart';

class WearGlassesCubit extends Cubit<WearGlassesState> {
  WearGlassesCubit() : super(WearGlassesState.initial());

  int _updateId = 0;
  int? _sessionEpoch;
  int _stateRevision = -1;

  void updateFromPayload(Map<String, dynamic> payload) {
    final dynamic rawEpoch = payload['sessionEpoch'];
    final dynamic rawRevision = payload['stateRevision'];
    final int? epoch = rawEpoch is num ? rawEpoch.toInt() : null;
    final int? revision = rawRevision is num ? rawRevision.toInt() : null;
    Map<String, dynamic> content = payload;
    if (epoch != null && revision != null) {
      final int? currentEpoch = _sessionEpoch;
      if (currentEpoch != null &&
          (epoch < currentEpoch ||
              (epoch == currentEpoch && revision <= _stateRevision))) {
        return;
      }
      final dynamic nested = payload['payload'];
      if (nested is! Map) return;
      _sessionEpoch = epoch;
      _stateRevision = revision;
      content = Map<String, dynamic>.from(nested);
    }
    final int receivedAtMillis = DateTime.now().millisecondsSinceEpoch;
    final WearGlassesState next = WearGlassesState.fromPayload(
      content,
      updateId: ++_updateId,
      payloadReceivedAtMillis: receivedAtMillis,
    );
    emit(next);
  }
}
