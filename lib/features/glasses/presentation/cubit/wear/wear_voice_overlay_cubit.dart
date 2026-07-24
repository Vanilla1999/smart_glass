import 'package:flutter_bloc/flutter_bloc.dart';

enum WearVoiceOverlayPhase {
  preparing,
  reconnecting,
  suspendedBySystem,
  unavailable,
}

class WearVoiceOverlayState {
  const WearVoiceOverlayState({
    this.visible = false,
    this.revision = 0,
    this.phase,
    this.reason,
    this.attempt = 0,
    this.message,
  });

  final bool visible;
  final int revision;
  final WearVoiceOverlayPhase? phase;
  final String? reason;
  final int attempt;
  final String? message;

  bool get isError => phase == WearVoiceOverlayPhase.unavailable;
}

class WearVoiceOverlayCubit extends Cubit<WearVoiceOverlayState> {
  WearVoiceOverlayCubit() : super(const WearVoiceOverlayState());

  void update(Map<String, dynamic> payload) {
    final bool visible = payload['visible'] == true;
    final int revision = payload['revision'] as int? ?? state.revision + 1;
    if (revision <= state.revision) return;
    final WearVoiceOverlayPhase? phase = switch (payload['phase'] as String?) {
      'preparing' => WearVoiceOverlayPhase.preparing,
      'reconnecting' => WearVoiceOverlayPhase.reconnecting,
      'suspendedBySystem' => WearVoiceOverlayPhase.suspendedBySystem,
      'unavailable' => WearVoiceOverlayPhase.unavailable,
      _ => null,
    };
    final String? message = payload['message'] as String?;
    emit(WearVoiceOverlayState(
      visible: visible,
      revision: revision,
      phase: phase,
      reason: payload['reason'] as String?,
      attempt: payload['attempt'] as int? ?? 0,
      message: message,
    ));
  }
}
