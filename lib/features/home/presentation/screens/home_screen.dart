import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/app/di/app_scope.dart';
import 'package:smart_glasses/features/home/presentation/cubit/home_cubit.dart';
import 'package:smart_glasses/features/home/presentation/cubit/home_state.dart';
import 'package:smart_glasses/features/home/presentation/widgets/barcode_display_card.dart';
import 'package:smart_glasses/features/home/presentation/widgets/control_buttons.dart';
import 'package:smart_glasses/features/home/presentation/widgets/counter_display.dart';
import 'package:smart_glasses/features/home/presentation/widgets/voice_recognition_button.dart';
import 'package:smart_glasses/features/scanner/presentation/cubit/scanner_cubit.dart';
import 'package:smart_glasses/features/scanner/presentation/cubit/scanner_state.dart';
import 'package:smart_glasses/features/voice/presentation/cubit/voice_cubit.dart';
import 'package:smart_glasses/features/voice/presentation/cubit/voice_state.dart';
import 'package:smart_glasses/modules/wear/navigation/wear_routes.dart';

/// Home screen
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dependencies = AppScope.of(context);

    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: dependencies.homeCubit),
        BlocProvider.value(value: dependencies.scannerCubit),
        BlocProvider.value(value: dependencies.voiceCubit),
      ],
      child: const _HomeScreenContent(),
    );
  }
}

class _HomeScreenContent extends StatelessWidget {
  const _HomeScreenContent();

  void _openWearModule(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderScope(
          child: MaterialApp.router(
            routerConfig: GoRouter(
              initialLocation: '/wear_main_screen',
              routes: WearRoute.goRouteWear,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: const Text('Smart Wear Test'),
        ),
        body: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                BlocBuilder<HomeCubit, HomeState>(
                  builder: (context, state) {
                    if (state is HomeLoaded) {
                      return ControlButtons(
                        onShowGlasses: () => context.read<HomeCubit>().showGlasses(),
                        onShowGlassesScreen2: () => context.read<HomeCubit>().showGlassesScreen2(),
                        onSaveLogs: () => context.read<HomeCubit>().saveLogs(),
                        onClearLogs: () => context.read<HomeCubit>().clearLogs(),
                        onIncrementCounter: () => context.read<HomeCubit>().incrementCounter(),
                        onPrintTags: () => _openWearModule(context),
                      );
                    }
                    return const CircularProgressIndicator();
                  },
                ),
                const SizedBox(height: 40),
                BlocBuilder<HomeCubit, HomeState>(
                  builder: (context, state) {
                    if (state is HomeLoaded) {
                      return CounterDisplay(counter: state.counter);
                    }
                    return const CounterDisplay(counter: 0);
                  },
                ),
                const SizedBox(height: 10),
                BlocBuilder<VoiceCubit, VoiceState>(
                  builder: (context, state) {
                    if (state is VoiceInitializing) {
                      return Text(
                        'Загрузка модели...',
                        style: Theme.of(context).textTheme.bodyMedium,
                      );
                    } else if (state is VoiceRecognized) {
                      return Text(
                        'Распознано: ${state.text}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      );
                    } else if (state is VoiceError) {
                      return Text(
                        'Ошибка: ${state.message}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.red),
                      );
                    }
                    return Text(
                      'Распознано: ',
                      style: Theme.of(context).textTheme.bodyMedium,
                    );
                  },
                ),
                const SizedBox(height: 20),
                BlocBuilder<ScannerCubit, ScannerState>(
                  builder: (context, state) {
                    String barcode = '';
                    if (state is ScannerScanned) {
                      barcode = state.barcode;
                    }
                    return BarcodeDisplayCard(barcode: barcode);
                  },
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            BlocBuilder<VoiceCubit, VoiceState>(
              builder: (context, state) {
                final isReady = state is VoiceReady || state is VoiceListening || state is VoiceRecognized;
                final isListening = state is VoiceListening;

                return VoiceRecognitionButton(
                  isReady: isReady,
                  isListening: isListening,
                  onPressed: () {
                    if (isListening) {
                      context.read<VoiceCubit>().stopListening();
                    } else {
                      context.read<VoiceCubit>().startListening();
                    }
                  },
                );
              },
            ),
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}
