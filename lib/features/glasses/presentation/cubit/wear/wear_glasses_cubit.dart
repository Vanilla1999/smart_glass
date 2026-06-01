import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/wear/wear_glasses_state.dart';

class WearGlassesCubit extends Cubit<WearGlassesState> {
  WearGlassesCubit() : super(WearGlassesState.initial());

  void updateFromPayload(Map<String, dynamic> payload) {
    emit(WearGlassesState.fromPayload(payload));
  }
}
