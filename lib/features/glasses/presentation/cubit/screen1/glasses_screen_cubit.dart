import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/screen1/glasses_screen_state.dart';

/// Cubit for managing glasses screen 1
class GlassesScreenCubit extends Cubit<GlassesScreenState> {
  GlassesScreenCubit() : super(const GlassesScreenInitial());

  int _counter = 0;
  String _recognizedText = '';

  /// Initialize screen
  void init({int initialCounter = 0}) {
    _counter = initialCounter;
    emit(GlassesScreenUpdated(counter: _counter, recognizedText: _recognizedText));
  }

  /// Update counter
  void updateCounter(int counter) {
    _counter = counter;
    emit(GlassesScreenUpdated(counter: _counter, recognizedText: _recognizedText));
  }

  /// Update recognized text
  void updateRecognizedText(String text) {
    _recognizedText = text;
    emit(GlassesScreenUpdated(counter: _counter, recognizedText: _recognizedText));
  }
}
