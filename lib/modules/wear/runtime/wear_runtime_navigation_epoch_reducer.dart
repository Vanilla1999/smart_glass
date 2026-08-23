import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

class WearEpochBoundPhoneRouteObserved extends WearIntent {
  const WearEpochBoundPhoneRouteObserved({
    required this.sessionEpoch,
    required this.screen,
    required this.observationRevision,
  });

  final int sessionEpoch;
  final WearScreenId screen;
  final int observationRevision;
}

class WearEpochBoundNavigationAcknowledged extends WearIntent {
  const WearEpochBoundNavigationAcknowledged({
    required this.sessionEpoch,
    required this.requestId,
    required this.screen,
  });

  final int sessionEpoch;
  final int requestId;
  final WearScreenId screen;
}

class WearSessionNavigationEpochReducer implements WearSliceReducer {
  const WearSessionNavigationEpochReducer();

  @override
  WearReduction? reduceSlice(WearRuntimeState state, WearIntent intent) {
    final WearAggregatePayload aggregate =
        state.payloadAs<WearAggregatePayload>();

    if (intent is WearSessionAuthorized) {
      final WearSessionSlice nextSession =
          WearSessionSlice.authorized(intent.user);
      if (aggregate.session.isAuthorized) {
        if (aggregate.session.sameIdentityAs(nextSession)) {
          return WearReduction.accept();
        }
        return WearReduction.reject(WearDispatchRejectReason.busy);
      }
      final WearFeaturePayload rawFeatures = aggregate.features;
      final WearFeaturePayload nextFeatures =
          rawFeatures is WearRuntimeFeaturePayload
              ? rawFeatures.copyWith(printer: rawFeatures.printer.reset())
              : rawFeatures;
      return WearReduction.accept(
        nextState: state.beginNextEpoch(
          legacy: WearLegacyRuntimeSnapshot(
            logicalScreen: aggregate.navigation.logicalScreen,
            sourceRevision: state.legacy.sourceRevision + 1,
          ),
          payload: aggregate.copyWith(
            session: nextSession,
            lifecycle: aggregate.lifecycle.copyWith(runtimeActive: true),
            controls: aggregate.controls.toTerminalControls(),
            features: nextFeatures,
          ),
        ),
      );
    }

    if (intent is WearEpochBoundPhoneRouteObserved) {
      if (intent.sessionEpoch < 0 || intent.observationRevision <= 0) {
        return WearReduction.reject(WearDispatchRejectReason.unsupported);
      }
      if (intent.sessionEpoch != state.sessionEpoch) {
        return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
      }
      if (intent.observationRevision <=
          aggregate.navigation.routeObservationRevision) {
        return WearReduction.reject(WearDispatchRejectReason.staleOperation);
      }
      return WearReduction.accept(
        nextState: state.withPayload(
          aggregate.copyWith(
            navigation: aggregate.navigation.observePhoneRoute(
              screen: intent.screen,
              observationRevision: intent.observationRevision,
            ),
          ),
        ),
      );
    }

    if (intent is WearEpochBoundNavigationAcknowledged) {
      if (intent.sessionEpoch < 0 || intent.requestId <= 0) {
        return WearReduction.reject(WearDispatchRejectReason.unsupported);
      }
      if (intent.sessionEpoch != state.sessionEpoch) {
        return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
      }
      final WearPendingNavigation? pending = aggregate.navigation.pending;
      if (pending == null ||
          pending.requestId != intent.requestId ||
          pending.screen != intent.screen) {
        return WearReduction.reject(WearDispatchRejectReason.staleOperation);
      }
      return WearReduction.accept(
        nextState: state.withPayload(
          aggregate.copyWith(
            navigation: aggregate.navigation.acknowledge(intent.screen),
          ),
        ),
      );
    }

    if (intent is WearPhoneRouteObserved ||
        intent is WearNavigationAcknowledged) {
      return WearReduction.reject(WearDispatchRejectReason.unsupported);
    }
    return null;
  }
}
