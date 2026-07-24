import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_glasses/core/services/method_channel_service.dart';
import 'package:smart_glasses/features/initialization/presentation/cubit/initialization_state.dart';
import 'package:smart_glasses/features/scanner/presentation/cubit/scanner_cubit.dart';
import 'package:smart_glasses/features/scanner/presentation/cubit/scanner_state.dart';
import 'package:smart_glasses/features/voice/presentation/cubit/voice_cubit.dart';
import 'package:smart_glasses/features/voice/presentation/cubit/voice_state.dart';

/// Cubit for managing initialization process
class InitializationCubit extends Cubit<InitializationState> {
  InitializationCubit({
    required ScannerCubit scannerCubit,
    required VoiceCubit voiceCubit,
    required MethodChannelService methodChannelService,
  })  : _scannerCubit = scannerCubit,
        _voiceCubit = voiceCubit,
        _methodChannelService = methodChannelService,
        super(const InitializationInProgress(
          scannerReady: false,
          voiceReady: false,
        ));

  final ScannerCubit _scannerCubit;
  final VoiceCubit _voiceCubit;
  final MethodChannelService _methodChannelService;

  StreamSubscription<ScannerState>? _scannerSub;
  StreamSubscription<VoiceState>? _voiceSub;

  bool _scannerReady = false;
  bool _voiceReady = false;

  /// Initialize all services
  Future<void> init() async {
    await _methodChannelService.showGlassesInitialization();
    
    _scannerSub = _scannerCubit.stream.listen((state) {
      if (state is ScannerReady) {
        _scannerReady = true;
        _updateState();
      }
    });

    _voiceSub = _voiceCubit.stream.listen((state) {
      if (state is VoiceReady) {
        _voiceReady = true;
        _updateState();
      }
    });

    if (_scannerCubit.state is ScannerReady) {
      _scannerReady = true;
    }
    if (_voiceCubit.state is VoiceReady) {
      _voiceReady = true;
    }

    final scannerFuture = _scannerCubit.init();
    final voiceFuture = _voiceCubit.init();

    await Future.any([
      voiceFuture,
      Future.delayed(const Duration(seconds: 30)),
    ]);

    if (_voiceCubit.state is VoiceReady) {
      _voiceReady = true;
    }

    await Future.any([
      scannerFuture,
      Future.delayed(const Duration(seconds: 10)),
    ]);

    if (_scannerCubit.state is ScannerReady) {
      _scannerReady = true;
    }

    _updateState();

    if (_voiceReady) {
      await _methodChannelService.navigateGlassesToEmpty();
    }
  }
  
  void _updateState() {
    if (isClosed) return;

    final newState = InitializationInProgress(
      scannerReady: _scannerReady,
      voiceReady: _voiceReady,
    );
    
    emit(newState);
    
    if (newState.isCompleted) {
      emit(const InitializationCompleted());
    }
  }

  @override
  Future<void> close() {
    _scannerSub?.cancel();
    _voiceSub?.cancel();
    return super.close();
  }
}
