import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

/// Owns the MR-S4 session/terminal reset shape.
///
/// Identity, controls and printer state cross one epoch boundary in one
/// committed snapshot. Route/request counters remain monotonic so late Flutter
/// callbacks cannot collide with the first operation of the next session.
class WearPrinterEpochResetReducer implements WearSliceReducer {
  const WearPrinterEpochResetReducer();

  @override
  WearReduction? reduceSlice(WearRuntimeState state, WearIntent intent) {
    final WearAggregatePayload aggregate =
        state.payloadAs<WearAggregatePayload>();
    final WearFeaturePayload rawFeatures = aggregate.features;
    if (rawFeatures is! WearRuntimeFeaturePayload) return null;

    if (intent is WearSessionCleared) {
      if (!aggregate.session.isAuthorized) return WearReduction.accept();
      final WearNavigationSlice previousNavigation = aggregate.navigation;
      final WearNavigationSlice resetNavigation = WearNavigationSlice(
        logicalScreen: WearScreenId.main,
        actualPhoneScreen: null,
        pending: null,
        history: const <WearScreenId>[WearScreenId.main],
        routeObservationRevision: previousNavigation.routeObservationRevision,
        nextRequestId: previousNavigation.nextRequestId,
      );
      final WearAggregatePayload nextPayload = aggregate.copyWith(
        session: const WearSessionSlice.anonymous(),
        lifecycle: aggregate.lifecycle.copyWith(runtimeActive: false),
        navigation: resetNavigation,
        controls: aggregate.controls.toTerminalControls(),
        features: rawFeatures.copyWith(
          printer: rawFeatures.printer.reset(),
        ),
      );
      return WearReduction.accept(
        nextState: state.beginNextEpoch(
          legacy: WearLegacyRuntimeSnapshot(
            logicalScreen: WearScreenId.main,
            sourceRevision: state.legacy.sourceRevision + 1,
          ),
          payload: nextPayload,
        ),
      );
    }

    if (intent is WearRuntimeTerminated) {
      final WearAggregatePayload terminalPayload = aggregate.copyWith(
        session: const WearSessionSlice.anonymous(),
        lifecycle: const WearLifecycleSlice(
          runtimeActive: false,
          phoneUiActive: false,
          terminal: true,
        ),
        navigation: aggregate.navigation.terminalized(),
        controls: aggregate.controls.toTerminalControls(),
        features: rawFeatures.copyWith(
          printer: rawFeatures.printer.reset(),
        ),
      );
      return WearReduction.accept(
        nextState: state.beginNextEpoch(
          legacy: WearLegacyRuntimeSnapshot(
            logicalScreen: aggregate.navigation.logicalScreen,
            sourceRevision: state.legacy.sourceRevision + 1,
          ),
          payload: terminalPayload,
          terminal: true,
        ),
      );
    }

    return null;
  }
}
