import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/screen2/glasses_screen2_state.dart';

/// Cubit for managing glasses screen 2
class GlassesScreen2Cubit extends Cubit<GlassesScreen2State> {
  GlassesScreen2Cubit() : super(const GlassesScreen2Initial());

  String _recognizedText = '';

  /// Initialize screen
  void init() {
    emit(GlassesScreen2Updated(recognizedText: _recognizedText));
  }

  /// Update recognized text
  void updateRecognizedText(String text) {
    _recognizedText = text;
    emit(GlassesScreen2Updated(recognizedText: _recognizedText));
  }
}
