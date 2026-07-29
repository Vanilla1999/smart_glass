import 'dart:async';

import 'package:smart_glasses/core/services/method_channel_service.dart';
import 'package:smart_glasses/core/voice/native_voice_capture.dart';
import 'package:smart_glasses/features/scanner/presentation/cubit/scanner_cubit.dart';
import 'package:smart_glasses/features/voice/presentation/cubit/voice_cubit.dart';
import 'package:smart_glasses/features/home/presentation/cubit/home_cubit.dart';
import 'package:smart_glasses/features/voice_memo/presentation/cubit/voice_memo_cubit.dart';
import 'package:smart_glasses/modules/wear/services/wear_voice_session.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';

/// Container for global dependencies
class DependenciesContainer {
  DependenciesContainer({
    required this.scannerCubit,
    required this.voiceCubit,
    required this.homeCubit,
    required this.voiceMemoCubit,
    required this.methodChannelService,
    required this.nativeVoiceCapture,
    required StreamSubscription<NativeVoiceStateEvent> nativeVoiceStateSub,
  }) : _nativeVoiceStateSub = nativeVoiceStateSub;

  final ScannerCubit scannerCubit;
  final VoiceCubit voiceCubit;
  final HomeCubit homeCubit;
  final VoiceMemoCubit voiceMemoCubit;
  final MethodChannelService methodChannelService;
  final NativeVoiceCapture nativeVoiceCapture;
  final StreamSubscription<NativeVoiceStateEvent> _nativeVoiceStateSub;

  /// Create dependencies container
  static Future<DependenciesContainer> create() async {
    final methodChannelService = MethodChannelService();
    final nativeVoiceCapture = NativeVoiceCapture.instance;
    final scannerCubit = ScannerCubit();
    final voiceCubit = VoiceCubit(methodChannelService, nativeVoiceCapture);
    final homeCubit = HomeCubit(methodChannelService);
    final voiceMemoCubit = VoiceMemoCubit(nativeVoiceCapture);
    final StreamSubscription<NativeVoiceStateEvent> nativeVoiceStateSub =
        nativeVoiceCapture.stateEvents.listen(
      (NativeVoiceStateEvent event) {
        WearVoiceSession.I.handleNativeVoiceState(event);
        voiceCubit.handleNativeVoiceState(event);
        unawaited(voiceMemoCubit.handleNativeVoiceState(event));
      },
      onError: (Object error, StackTrace stackTrace) {
        print('Native voice state stream failed: $error\n$stackTrace');
      },
    );

    // Initialize only homeCubit synchronously
    // Scanner and Voice initialization will be managed by InitializationCubit
    homeCubit.init();

    return DependenciesContainer(
      scannerCubit: scannerCubit,
      voiceCubit: voiceCubit,
      homeCubit: homeCubit,
      voiceMemoCubit: voiceMemoCubit,
      methodChannelService: methodChannelService,
      nativeVoiceCapture: nativeVoiceCapture,
      nativeVoiceStateSub: nativeVoiceStateSub,
    );
  }

  /// Dispose all resources
  Future<void> dispose() async {
    await WearVoiceSession.I.stop();
    await _nativeVoiceStateSub.cancel();
    await WearDependencies.I.disposeVoiceServices();
    await voiceCubit.close();
    await voiceMemoCubit.close();
    await nativeVoiceCapture.dispose();
    await scannerCubit.close();
    await homeCubit.close();
  }
}
