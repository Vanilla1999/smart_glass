import 'package:smart_glasses/core/services/method_channel_service.dart';
import 'package:smart_glasses/features/scanner/presentation/cubit/scanner_cubit.dart';
import 'package:smart_glasses/features/voice/presentation/cubit/voice_cubit.dart';
import 'package:smart_glasses/features/home/presentation/cubit/home_cubit.dart';

/// Container for global dependencies
class DependenciesContainer {
  const DependenciesContainer({
    required this.scannerCubit,
    required this.voiceCubit,
    required this.homeCubit,
    required this.methodChannelService,
  });

  final ScannerCubit scannerCubit;
  final VoiceCubit voiceCubit;
  final HomeCubit homeCubit;
  final MethodChannelService methodChannelService;

  /// Create dependencies container
  static Future<DependenciesContainer> create() async {
    final methodChannelService = MethodChannelService();
    final scannerCubit = ScannerCubit();
    final voiceCubit = VoiceCubit(methodChannelService);
    final homeCubit = HomeCubit(methodChannelService);

    // Initialize only homeCubit synchronously
    // Scanner and Voice initialization will be managed by InitializationCubit
    homeCubit.init();

    return DependenciesContainer(
      scannerCubit: scannerCubit,
      voiceCubit: voiceCubit,
      homeCubit: homeCubit,
      methodChannelService: methodChannelService,
    );
  }

  /// Dispose all resources
  Future<void> dispose() async {
    await scannerCubit.close();
    await voiceCubit.close();
    await homeCubit.close();
  }
}
