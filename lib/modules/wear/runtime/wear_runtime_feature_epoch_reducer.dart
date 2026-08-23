import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_availability_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_control_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_scan_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_semantic_inputs.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

/// Owns epoch transitions once all business feature slices are aggregate-owned.
///
/// This reducer must be before session/navigation and feature reducers so auth,
/// logout and terminal transitions cannot publish a snapshot containing state
/// from an older feature epoch.
class WearRuntimeFeatureEpochReducer implements WearSliceReducer {
  const WearRuntimeFeatureEpochReducer();

  @override
  WearReduction? reduceSlice(WearRuntimeState state, WearIntent intent) {
    final WearAggregatePayload aggregate =
        state.payloadAs<WearAggregatePayload>();
    final WearFeaturePayload rawFeatures = aggregate.features;
    final WearControlPayload rawControls = aggregate.controls;
    if (rawFeatures is! WearRuntimeFeaturePayload ||
        rawFeatures.scan is! WearScanTaskSlice ||
        rawFeatures.availability is! WearAvailabilityTaskSlice ||
        rawControls is! WearRuntimeControlPayload) {
      return null;
    }
    final WearScanTaskSlice scan = rawFeatures.scan as WearScanTaskSlice;
    final WearAvailabilityTaskSlice availability =
        rawFeatures.availability as WearAvailabilityTaskSlice;
    final WearRuntimeControlPayload controls = rawControls;

    if (intent is WearSessionAuthorized) {
      final WearSessionSlice requested =
          WearSessionSlice.authorized(intent.user);
      if (aggregate.session.isAuthorized) {
        if (aggregate.session.sameIdentityAs(requested)) {
          return WearReduction.accept();
        }
        return WearReduction.reject(WearDispatchRejectReason.busy);
      }
      return WearReduction.accept(
        nextState: state.beginNextEpoch(
          legacy: WearLegacyRuntimeSnapshot(
            logicalScreen: aggregate.navigation.logicalScreen,
            sourceRevision: state.legacy.sourceRevision + 1,
          ),
          payload: aggregate.copyWith(
            session: requested,
            lifecycle: aggregate.lifecycle.copyWith(runtimeActive: true),
            controls: controls.toTerminalControls(),
            uiEffects: WearUiEffectSlice(
              nextEffectId: aggregate.uiEffects.nextEffectId,
            ),
            features: rawFeatures.copyWith(
              printer: rawFeatures.printer.reset(),
              scan: scan.reset(),
              availability: availability.reset(),
            ),
          ),
        ),
      );
    }

    if (intent is WearSessionCleared) {
      if (!aggregate.session.isAuthorized) return WearReduction.accept();
      final WearNavigationSlice previous = aggregate.navigation;
      final int requestId = previous.nextRequestId + 1;
      final WearNavigationSlice navigation = WearNavigationSlice(
        logicalScreen: WearScreenId.main,
        actualPhoneScreen: previous.actualPhoneScreen,
        pending: WearPendingNavigation(
          requestId: requestId,
          screen: WearScreenId.main,
          kind: WearPendingNavigationKind.replace,
        ),
        history: const <WearScreenId>[WearScreenId.main],
        routeObservationRevision: previous.routeObservationRevision,
        nextRequestId: requestId,
      );
      return WearReduction.accept(
        nextState: state.beginNextEpoch(
          legacy: WearLegacyRuntimeSnapshot(
            logicalScreen: WearScreenId.main,
            sourceRevision: state.legacy.sourceRevision + 1,
          ),
          payload: aggregate.copyWith(
            session: const WearSessionSlice.anonymous(),
            lifecycle: aggregate.lifecycle.copyWith(runtimeActive: true),
            navigation: navigation,
            controls: controls.toTerminalControls(),
            uiEffects: WearUiEffectSlice(
              nextEffectId: aggregate.uiEffects.nextEffectId,
            ),
            features: rawFeatures.copyWith(
              printer: rawFeatures.printer.reset(),
              scan: scan.reset(),
              availability: availability.reset(),
            ),
          ),
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
        controls: controls.toTerminalControls(),
        uiEffects: WearUiEffectSlice(
          nextEffectId: aggregate.uiEffects.nextEffectId,
        ),
        features: rawFeatures.copyWith(
          printer: rawFeatures.printer.reset(),
          scan: scan.reset(),
          availability: availability.reset(),
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
