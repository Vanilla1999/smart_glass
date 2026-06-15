import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/screen3/glasses_screen3_cubit.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/screen3/glasses_screen3_state.dart';

class GlassesScreen3 extends StatelessWidget {
  const GlassesScreen3({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: BlocBuilder<GlassesScreen3Cubit, GlassesScreen3State>(
        builder: (context, state) {
          return Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(color: Colors.black),
            child: const Image(
              image: AssetImage('assets/test.png'),
              fit: BoxFit.contain,
            ),
          );
        },
      ),
    );
  }
}
