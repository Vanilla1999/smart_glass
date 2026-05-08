import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_glasses/app/di/app_scope.dart';
import 'package:smart_glasses/features/home/presentation/screens/home_screen.dart';
import 'package:smart_glasses/features/initialization/presentation/cubit/initialization_cubit.dart';
import 'package:smart_glasses/features/initialization/presentation/cubit/initialization_state.dart';

/// Initialization screen
class InitializationScreen extends StatelessWidget {
  const InitializationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dependencies = AppScope.of(context);

    return BlocProvider(
      create: (_) => InitializationCubit(
        scannerCubit: dependencies.scannerCubit,
        voiceCubit: dependencies.voiceCubit,
        methodChannelService: dependencies.methodChannelService,
      )..init(),
      child: const _InitializationScreenContent(),
    );
  }
}

class _InitializationScreenContent extends StatelessWidget {
  const _InitializationScreenContent();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocConsumer<InitializationCubit, InitializationState>(
        listener: (context, state) {
          if (state is InitializationCompleted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const HomeScreen()),
            );
          }
        },
        builder: (context, state) {
          if (state is InitializationInProgress) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Инициализация',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 40),
                    
                    // Scanner status
                    _StatusRow(
                      label: 'Подключение к сканеру',
                      isReady: state.scannerReady,
                    ),
                    const SizedBox(height: 16),
                    
                    // Vosk status
                    _StatusRow(
                      label: 'Загрузка модели распознавания',
                      isReady: state.voiceReady,
                    ),
                    const SizedBox(height: 40),
                    
                    // Progress bar
                    LinearProgressIndicator(
                      value: state.progress,
                      minHeight: 8,
                    ),
                    const SizedBox(height: 16),
                    
                    // Percentage
                    Text(
                      '${(state.progress * 100).toInt()}%',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.isReady,
  });

  final String label;
  final bool isReady;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          isReady ? Icons.check_circle : Icons.hourglass_empty,
          color: isReady ? Colors.green : Colors.grey,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: isReady ? Colors.green : Colors.grey,
            ),
          ),
        ),
      ],
    );
  }
}
