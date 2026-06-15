import 'package:flutter/widgets.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/wear/wear_glasses_state.dart';

class GlassesPreviewNotifier extends ChangeNotifier {
  GlassesPreviewNotifier._();

  static final GlassesPreviewNotifier I = GlassesPreviewNotifier._();

  WearGlassesState _state = WearGlassesState.initial();
  
  WearGlassesState get state => _state;

  void updateFromPayload(Map<String, dynamic> payload) {
    _state = WearGlassesState.fromPayload(payload);
    notifyListeners();
  }
}

class GlassesPreviewProvider extends InheritedNotifier<GlassesPreviewNotifier> {
  const GlassesPreviewProvider({
    super.key,
    required GlassesPreviewNotifier notifier,
    required super.child,
  }) : super(notifier: notifier);

  static GlassesPreviewNotifier of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<GlassesPreviewProvider>();
    return provider?.notifier ?? GlassesPreviewNotifier.I;
  }
}
