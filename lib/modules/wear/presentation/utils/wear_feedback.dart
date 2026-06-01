import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';

class WearFeedback {
  WearFeedback._();

  static const MethodChannel _channel = MethodChannel('nbo_app');
  static const Duration _suppressAfterSleep = Duration(seconds: 3);
  static DateTime? _lastPlayedAt;
  static WearStatusKind? _lastKind;
  static bool _lastFromSleeping = false;

  static Future<void> play(
    WearStatusKind kind, {
    bool onlyWhenSleeping = false,
  }) async {
    if (onlyWhenSleeping) {
      final AppLifecycleState? state = WidgetsBinding.instance.lifecycleState;
      if (state == AppLifecycleState.resumed) {
        return;
      }
    }
    await _playFeedback(kind);
  }

  static Future<void> _playFeedback(WearStatusKind kind) async {
    try {
      await _channel.invokeMethod<void>(
        'playWearStatusSound',
        <String, dynamic>{'kind': kind.name},
      );
    } catch (_) {}

    try {
      await Haptics.vibrate(
        kind == WearStatusKind.success
            ? HapticsType.success
            : HapticsType.error,
      );
    } catch (_) {}

    _lastPlayedAt = DateTime.now();
    _lastKind = kind;
    _lastFromSleeping =
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed;
  }
}
