import 'package:smart_glasses/modules/wear/application/runtime/wear_runtime_state.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_state.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';

class WearRuntimeSelectors {
  const WearRuntimeSelectors._();

  static WearScreenId logicalScreen(WearRuntimeState state) {
    return state.legacy.flow.screen;
  }

  static WearFlowState legacyFlow(WearRuntimeState state) {
    return state.legacy.flow;
  }

  static WearFlowState phoneFlowProjection(WearRuntimeState state) {
    return state.legacy.flow;
  }

  static WearFlowState glassesFlowProjection(WearRuntimeState state) {
    return state.legacy.flow;
  }
}
