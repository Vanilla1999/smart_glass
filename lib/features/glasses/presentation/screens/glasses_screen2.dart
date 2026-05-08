import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/screen2/glasses_screen2_cubit.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/screen2/glasses_screen2_state.dart';

/// Glasses screen 2
class GlassesScreen2 extends StatelessWidget {
  const GlassesScreen2({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: BlocBuilder<GlassesScreen2Cubit, GlassesScreen2State>(
          builder: (context, state) {
            if (state is GlassesScreen2Updated) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Экран 2',
                    style: TextStyle(
                      color: Color(0xFF00FF00),
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF00FF00), width: 2),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'РАСПОЗНАННЫЙ ТЕКСТ',
                          style: TextStyle(
                            color: Color(0xFF00FF00),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          state.recognizedText.isEmpty ? 'Нет данных' : state.recognizedText,
                          style: const TextStyle(
                            color: Color(0xFF00FF00),
                            fontSize: 24,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
            return const CircularProgressIndicator(color: Color(0xFF00FF00));
          },
        ),
      ),
    );
  }
}
