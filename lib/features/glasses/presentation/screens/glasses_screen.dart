import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/screen1/glasses_screen_cubit.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/screen1/glasses_screen_state.dart';
import 'package:smart_glasses/features/glasses/presentation/widgets/glasses_status_widget.dart';

/// Glasses screen 1 (with progress bar)
class GlassesScreen extends StatelessWidget {
  const GlassesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: BlocBuilder<GlassesScreenCubit, GlassesScreenState>(
          builder: (context, state) {
            if (state is GlassesScreenUpdated) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GlassesStatusWidget(
                    counter: state.counter,
                    recognizedText: state.recognizedText,
                  ),
                  const SizedBox(height: 20),
                  const SizedBox(
                    width: 200,
                    height: 200,
                    child: CircularProgressIndicator(color: Color(0xFF00FF00)),
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
