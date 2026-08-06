import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:multi_scanner/multi_scanner.dart';
import 'package:smart_glasses/core/services/method_channel_service.dart';
import 'package:smart_glasses/features/home/presentation/cubit/home_state.dart';

/// Cubit for managing home screen
class HomeCubit extends Cubit<HomeState> {
  HomeCubit(this._methodChannelService) : super(const HomeInitial());

  final MethodChannelService _methodChannelService;
  int _counter = 0;
  int? _flashlightState;

  /// Initialize home screen
  void init() {
    emit(HomeLoaded(counter: _counter, flashlightState: _flashlightState));
  }

  /// Toggle glasses flashlight (same logic as WearFlowController._toggleScannerFlashlight)
  Future<void> toggleFlashlight() async {
    final controller = MovfastGlassController();
    final hardwareState = await controller.getFlashlightState();
    final currentState = _flashlightState ?? hardwareState;
    final targetState = currentState == 1 ? 0 : 1;
    print(
      '[HomeCubit] flashlight hardware=$hardwareState '
      'tracked=$currentState target=$targetState',
    );
    await controller.setFlashlight(targetState);
    _flashlightState = targetState;
    emit(HomeLoaded(counter: _counter, flashlightState: _flashlightState));
  }

  /// Increment counter
  Future<void> incrementCounter() async {
    _counter++;
    emit(HomeLoaded(counter: _counter));
    await _methodChannelService.updateCounter(_counter);
  }

  /// Save logs to file
  Future<void> saveLogs() async {
    await _methodChannelService.saveLogs();
  }

  /// Clear logs
  Future<void> clearLogs() async {
    await _methodChannelService.clearLogs();
  }
}
