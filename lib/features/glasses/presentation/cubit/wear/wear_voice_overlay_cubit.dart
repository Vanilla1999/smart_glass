import 'package:flutter_bloc/flutter_bloc.dart';

class WearVoiceOverlayState {
  const WearVoiceOverlayState({
    this.visible = false,
    this.message,
  });

  final bool visible;
  final String? message;

  bool get isError => message == 'Голосовое управление недоступно';
}

class WearVoiceOverlayCubit extends Cubit<WearVoiceOverlayState> {
  WearVoiceOverlayCubit() : super(const WearVoiceOverlayState());

  void update(Map<String, dynamic> payload) {
    final bool visible = payload['visible'] == true;
    final String? message = payload['message'] as String?;
    emit(WearVoiceOverlayState(visible: visible, message: message));
  }
}
