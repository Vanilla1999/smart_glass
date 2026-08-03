import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_glasses/app/glasses/glasses_coordinator_state.dart';
import 'package:smart_glasses/core/services/method_channel_service.dart';

/// Coordinator cubit for managing glasses runtime
/// Handles MethodChannel events and routes them to appropriate screen cubits
class GlassesCoordinatorCubit extends Cubit<GlassesCoordinatorState> {
  GlassesCoordinatorCubit({
    required MethodChannelService methodChannelService,
    required this.onNavigateToScreen,
    required this.onNavigateHome,
    required this.onUpdateScreen1Counter,
    required this.onUpdateScreen1RecognizedText,
    required this.onUpdateScreen2RecognizedText,
    required this.onUpdateWearGlasses,
    this.onUpdateWearVoiceOverlay = _ignoreWearVoiceOverlay,
  })  : _methodChannelService = methodChannelService,
        super(const GlassesCoordinatorInitial());

  final MethodChannelService _methodChannelService;

  // Navigation callbacks
  final Function(String route) onNavigateToScreen;
  final Function() onNavigateHome;

  // Screen 1 data callbacks
  final Function(int counter) onUpdateScreen1Counter;
  final Function(String text) onUpdateScreen1RecognizedText;

  // Screen 2 data callbacks
  final Function(String text) onUpdateScreen2RecognizedText;

  // Wear projection callbacks
  final Function(Map<String, dynamic> payload) onUpdateWearGlasses;
  final Function(Map<String, dynamic> payload) onUpdateWearVoiceOverlay;

  String _currentRoute = '/';

  /// Initialize coordinator
  Future<void> init() async {
    _methodChannelService.setGlassesMethodCallHandler(_handleMethodCall);
    final counter = await _methodChannelService.getInitialCounter();
    onUpdateScreen1Counter(counter);
    emit(GlassesCoordinatorReady(currentRoute: _currentRoute));
  }

  /// Handle method calls from native
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'navigateToScreen':
        _handleNavigateToScreen(call.arguments);
        break;
      case 'navigateToRoute':
        _handleNavigateToRoute(call.arguments);
        break;
      case 'updateCounter':
        _handleUpdateCounter(call.arguments as int);
        break;
      case 'updateRecognizedText':
        _handleUpdateRecognizedText(call.arguments as String? ?? '');
        break;
      case 'updateWearGlasses':
        _handleUpdateWearGlasses(call.arguments);
        break;
      case 'updateWearVoiceOverlay':
        _handleUpdateWearVoiceOverlay(call.arguments);
        break;
    }
  }

  /// Handle navigation to screen
  void _handleNavigateToScreen(dynamic arguments) {
    if (arguments is Map) {
      final route = arguments['route'] as String?;
      if (route != null) {
        _currentRoute = route;
        onNavigateToScreen(route);
        emit(GlassesCoordinatorReady(currentRoute: _currentRoute));
      }
    }
  }

  /// Handle navigation to route
  void _handleNavigateToRoute(dynamic arguments) {
    if (arguments is String) {
      if (arguments == '/') {
        _currentRoute = '/';
        onNavigateHome();
        emit(GlassesCoordinatorReady(currentRoute: _currentRoute));
      } else {
        _currentRoute = arguments;
        onNavigateToScreen(arguments);
        emit(GlassesCoordinatorReady(currentRoute: _currentRoute));
      }
    }
  }

  /// Handle counter update - route to active screen
  void _handleUpdateCounter(int counter) {
    // Route data based on current active screen
    if (_currentRoute == '/' || _currentRoute == '/screen1') {
      onUpdateScreen1Counter(counter);
    }
    // Screen2 doesn't use counter, so we ignore it for that screen
  }

  /// Handle recognized text update - route to active screen
  void _handleUpdateRecognizedText(String text) {
    // Route data based on current active screen
    if (_currentRoute == '/' || _currentRoute == '/screen1') {
      onUpdateScreen1RecognizedText(text);
    } else if (_currentRoute == '/screen2') {
      onUpdateScreen2RecognizedText(text);
    }
  }

  void _handleUpdateWearGlasses(dynamic arguments) {
    if (arguments is Map) {
      onUpdateWearGlasses(Map<String, dynamic>.from(arguments));
    }
  }

  void _handleUpdateWearVoiceOverlay(dynamic arguments) {
    if (arguments is Map) {
      onUpdateWearVoiceOverlay(Map<String, dynamic>.from(arguments));
    }
  }

  static void _ignoreWearVoiceOverlay(Map<String, dynamic> payload) {}
}
