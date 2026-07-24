import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_glasses/app/glasses/glasses_coordinator_cubit.dart';
import 'package:smart_glasses/core/services/method_channel_service.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/screen1/glasses_screen_cubit.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/screen2/glasses_screen2_cubit.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/wear/wear_glasses_cubit.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/wear/wear_voice_overlay_cubit.dart';
import 'package:smart_glasses/features/glasses/presentation/screens/glasses_screen.dart';
import 'package:smart_glasses/features/glasses/presentation/screens/glasses_screen2.dart';
import 'package:smart_glasses/features/glasses/presentation/screens/glasses_initialization_screen.dart';
import 'package:smart_glasses/features/glasses/presentation/screens/glasses_empty_screen.dart';
import 'package:smart_glasses/features/glasses/presentation/screens/wear/wear_glasses_screen.dart';
import 'package:smart_glasses/features/glasses/presentation/widgets/sequential_fade_route.dart';

/// Glasses runtime app - отдельный класс для работы с glasses экранами
/// Инкапсулирует всю логику glasses-подсистемы
class GlassesRuntimeApp extends StatefulWidget {
  const GlassesRuntimeApp({super.key});

  @override
  State<GlassesRuntimeApp> createState() => _GlassesRuntimeAppState();
}

class _GlassesRuntimeAppState extends State<GlassesRuntimeApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  late final GlassesCoordinatorCubit _coordinatorCubit;
  late final GlassesScreenCubit _screen1Cubit;
  late final GlassesScreen2Cubit _screen2Cubit;
  late final WearGlassesCubit _wearGlassesCubit;
  late final WearVoiceOverlayCubit _wearVoiceOverlayCubit;

  @override
  void initState() {
    super.initState();

    // Create screen cubits
    _screen1Cubit = GlassesScreenCubit();
    _screen2Cubit = GlassesScreen2Cubit();
    _wearGlassesCubit = WearGlassesCubit();
    _wearVoiceOverlayCubit = WearVoiceOverlayCubit();

    // Create coordinator with callbacks
    _coordinatorCubit = GlassesCoordinatorCubit(
      methodChannelService: MethodChannelService(),
      onNavigateToScreen: _navigateTo,
      onNavigateHome: _navigateHome,
      onUpdateScreen1Counter: _screen1Cubit.updateCounter,
      onUpdateScreen1RecognizedText: _screen1Cubit.updateRecognizedText,
      onUpdateScreen2RecognizedText: _screen2Cubit.updateRecognizedText,
      onUpdateWearGlasses: _wearGlassesCubit.updateFromPayload,
      onUpdateWearVoiceOverlay: _wearVoiceOverlayCubit.update,
    );

    // Initialize coordinator
    _coordinatorCubit.init();

    // Initialize screens
    _screen1Cubit.init();
    _screen2Cubit.init();
  }

  @override
  void dispose() {
    _coordinatorCubit.close();
    _screen1Cubit.close();
    _screen2Cubit.close();
    _wearGlassesCubit.close();
    _wearVoiceOverlayCubit.close();
    super.dispose();
  }

  Widget _buildScreen(String routeName) {
    switch (routeName) {
      case '/initialization':
        return const GlassesInitializationScreen();
      case '/empty':
        return const GlassesEmptyScreen();
      case '/screen2':
        return const GlassesScreen2();
      case '/wear':
        return const WearGlassesScreen();
      default:
        return const GlassesScreen();
    }
  }

  void _navigateTo(String routeName) {
    _navigatorKey.currentState?.push(
      SequentialFadeRoute(
        builder: (context) => _buildScreen(routeName),
      ),
    );
  }

  void _navigateHome() {
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _coordinatorCubit),
        BlocProvider.value(value: _screen1Cubit),
        BlocProvider.value(value: _screen2Cubit),
        BlocProvider.value(value: _wearGlassesCubit),
        BlocProvider.value(value: _wearVoiceOverlayCubit),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        debugShowCheckedModeBanner: false,
        onGenerateRoute: (settings) {
          return SequentialFadeRoute(
            builder: (context) => _buildScreen(settings.name ?? '/'),
          );
        },
      ),
    );
  }
}
