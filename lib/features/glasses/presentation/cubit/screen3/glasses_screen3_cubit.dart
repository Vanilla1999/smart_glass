import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/screen3/glasses_screen3_state.dart';

class GlassesScreen3Cubit extends Cubit<GlassesScreen3State> {
  GlassesScreen3Cubit() : super(const GlassesScreen3Initial());

  void init() {
    emit(const GlassesScreen3Updated());
  }
}
