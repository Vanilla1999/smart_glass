import 'dart:collection';

import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_availability_review_reducer.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_availability_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_scan_review_reducers.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_scan_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

enum WearInputModality { touch, voice, button, barcode, manual }

enum WearSemanticInputKind { barcode, requestUiEffect, presentationFocus }

class WearSemanticInput extends WearIntent {
  const WearSemanticInput({
    required this.kind,
    required this.modality,
    required this.expectedScreen,
    required this.expectedSessionEpoch,
    this.value,
    this.uiEffectKind,
    this.focusIndex,
  });

  final WearSemanticInputKind kind;
  final WearInputModality modality;
  final WearScreenId expectedScreen;
  final int expectedSessionEpoch;
  final String? value;
  final WearUiEffectKind? uiEffectKind;
  final int? focusIndex;
}

enum WearUiEffectKind { manualBarcodeInput, systemWifiSettings, confirmationDialog }

enum WearUiEffectStatus { pending, claimed, completed, cancelled }

enum WearInactivePhoneUiPolicy { defer }

class WearUiEffect {
  const WearUiEffect({
    required this.effectId,
    required this.sessionEpoch,
    required this.kind,
    required this.expectedScreen,
    required this.createdRevision,
    required this.status,
  });

  final int effectId;
  final int sessionEpoch;
  final WearUiEffectKind kind;
  final WearScreenId expectedScreen;
  final int createdRevision;
  final WearUiEffectStatus status;

  WearUiEffect claimed() => WearUiEffect(
        effectId: effectId,
        sessionEpoch: sessionEpoch,
        kind: kind,
        expectedScreen: expectedScreen,
        createdRevision: createdRevision,
        status: WearUiEffectStatus.claimed,
      );
}

class WearUiEffectSlice {
  WearUiEffectSlice({
    Iterable<WearUiEffect> effects = const <WearUiEffect>[],
    this.nextEffectId = 0,
  }) : effects = UnmodifiableListView<WearUiEffect>(
          List<WearUiEffect>.unmodifiable(effects),
        );

  static const WearInactivePhoneUiPolicy inactivePhonePolicy =
      WearInactivePhoneUiPolicy.defer;

  final UnmodifiableListView<WearUiEffect> effects;
  final int nextEffectId;

  WearUiEffect? effectOfKind(WearUiEffectKind kind) {
    for (final WearUiEffect effect in effects) {
      if (effect.kind == kind) return effect;
    }
    return null;
  }

  WearUiEffectSlice add({
    required int sessionEpoch,
    required WearUiEffectKind kind,
    required WearScreenId expectedScreen,
    required int createdRevision,
  }) {
    final int id = nextEffectId + 1;
    return WearUiEffectSlice(
      effects: <WearUiEffect>[
        ...effects,
        WearUiEffect(
          effectId: id,
          sessionEpoch: sessionEpoch,
          kind: kind,
          expectedScreen: expectedScreen,
          createdRevision: createdRevision,
          status: WearUiEffectStatus.pending,
        ),
      ],
      nextEffectId: id,
    );
  }

  WearUiEffectSlice claim(int effectId) => _replace(
        effectId,
        (WearUiEffect effect) => effect.claimed(),
      );

  WearUiEffectSlice remove(int effectId) => WearUiEffectSlice(
        effects: effects.where((WearUiEffect effect) {
          return effect.effectId != effectId;
        }),
        nextEffectId: nextEffectId,
      );

  WearUiEffectSlice _replace(
    int effectId,
    WearUiEffect Function(WearUiEffect effect) replace,
  ) {
    return WearUiEffectSlice(
      effects: effects.map((WearUiEffect effect) {
        return effect.effectId == effectId ? replace(effect) : effect;
      }),
      nextEffectId: nextEffectId,
    );
  }
}

class WearUiEffectClaimed extends WearIntent {
  const WearUiEffectClaimed({
    required this.effectId,
    required this.sessionEpoch,
    required this.expectedScreen,
  });

  final int effectId;
  final int sessionEpoch;
  final WearScreenId expectedScreen;
}

class WearUiEffectCompleted extends WearIntent {
  const WearUiEffectCompleted({
    required this.effectId,
    required this.sessionEpoch,
    required this.expectedScreen,
    this.value,
  });

  final int effectId;
  final int sessionEpoch;
  final WearScreenId expectedScreen;
  final Object? value;
}

class WearUiEffectCancelled extends WearIntent {
  const WearUiEffectCancelled({
    required this.effectId,
    required this.sessionEpoch,
    required this.expectedScreen,
  });

  final int effectId;
  final int sessionEpoch;
  final WearScreenId expectedScreen;
}

class WearSemanticInputReducer implements WearSliceReducer {
  const WearSemanticInputReducer();

  @override
  WearReduction? reduceSlice(WearRuntimeState state, WearIntent intent) {
    final WearAggregatePayload aggregate = state.payloadAs<WearAggregatePayload>();
    if (intent is WearSemanticInput) {
      if (intent.expectedSessionEpoch != state.sessionEpoch) {
        return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
      }
      if (intent.expectedScreen != aggregate.navigation.logicalScreen) {
        return WearReduction.reject(WearDispatchRejectReason.staleScreen);
      }
      switch (intent.kind) {
        case WearSemanticInputKind.barcode:
          final String barcode = intent.value?.trim() ?? '';
          if (barcode.isEmpty) {
            return WearReduction.reject(WearDispatchRejectReason.unsupported);
          }
          if (intent.expectedScreen == WearScreenId.scanIdle) {
            return const WearReviewedScanSliceReducer().reduceSlice(
              state,
              WearScanBarcodeReceived(barcode),
            );
          }
          return const WearReviewedAvailabilitySliceReducer().reduceSlice(
                state,
                WearAvailabilityBarcodeReceived(barcode),
              ) ??
              WearReduction.reject(WearDispatchRejectReason.unsupported);
        case WearSemanticInputKind.requestUiEffect:
          final WearUiEffectKind? kind = intent.uiEffectKind;
          if (kind == null) {
            return WearReduction.reject(WearDispatchRejectReason.unsupported);
          }
          if (aggregate.uiEffects.effectOfKind(kind) != null) {
            return WearReduction.reject(WearDispatchRejectReason.duplicate);
          }
          return WearReduction.accept(
            nextState: state.withPayload(aggregate.copyWith(
              uiEffects: aggregate.uiEffects.add(
                sessionEpoch: state.sessionEpoch,
                kind: kind,
                expectedScreen: intent.expectedScreen,
                createdRevision: state.revision + 1,
              ),
            )),
          );
        case WearSemanticInputKind.presentationFocus:
          final int? index = intent.focusIndex;
          if (index == null ||
              index < 0 ||
              !_ownsPresentationFocus(intent.expectedScreen)) {
            return WearReduction.reject(WearDispatchRejectReason.unsupported);
          }
          final WearPresentationFocusSlice presentation =
              aggregate.presentation as WearPresentationFocusSlice;
          if (presentation.focusFor(intent.expectedScreen) == index) {
            return WearReduction.accept();
          }
          return WearReduction.accept(
            nextState: state.withPayload(aggregate.copyWith(
              presentation: presentation.withFocus(intent.expectedScreen, index),
            )),
          );
      }
    }

    if (intent is WearUiEffectClaimed) {
      return _finish(state, aggregate, intent.effectId, intent.sessionEpoch,
          intent.expectedScreen, claim: true);
    }
    if (intent is WearUiEffectCompleted) {
      return _finish(state, aggregate, intent.effectId, intent.sessionEpoch,
          intent.expectedScreen, requireClaimed: true);
    }
    if (intent is WearUiEffectCancelled) {
      return _finish(state, aggregate, intent.effectId, intent.sessionEpoch,
          intent.expectedScreen, allowScreenChange: true);
    }
    return null;
  }

  WearReduction _finish(
    WearRuntimeState state,
    WearAggregatePayload aggregate,
    int effectId,
    int sessionEpoch,
    WearScreenId expectedScreen, {
    bool claim = false,
    bool requireClaimed = false,
    bool allowScreenChange = false,
  }) {
    if (sessionEpoch != state.sessionEpoch) {
      return WearReduction.reject(WearDispatchRejectReason.staleEpoch);
    }
    WearUiEffect? effect;
    for (final WearUiEffect candidate in aggregate.uiEffects.effects) {
      if (candidate.effectId == effectId) {
        effect = candidate;
        break;
      }
    }
    if (effect == null) {
      return WearReduction.reject(WearDispatchRejectReason.staleOperation);
    }
    if (effect.expectedScreen != expectedScreen ||
        (!allowScreenChange &&
            expectedScreen != aggregate.navigation.logicalScreen)) {
      return WearReduction.reject(WearDispatchRejectReason.staleScreen);
    }
    if (claim && !aggregate.lifecycle.phoneUiActive) {
      return WearReduction.reject(WearDispatchRejectReason.busy);
    }
    if (claim && effect.status == WearUiEffectStatus.claimed) {
      return WearReduction.accept();
    }
    if (requireClaimed && effect.status != WearUiEffectStatus.claimed) {
      return WearReduction.reject(WearDispatchRejectReason.staleOperation);
    }
    final WearUiEffectSlice next = claim
        ? aggregate.uiEffects.claim(effectId)
        : aggregate.uiEffects.remove(effectId);
    return WearReduction.accept(
      nextState: state.withPayload(aggregate.copyWith(uiEffects: next)),
    );
  }

  bool _ownsPresentationFocus(WearScreenId screen) {
    return screen == WearScreenId.menu ||
        screen == WearScreenId.homeConfirm ||
        screen == WearScreenId.continueScan ||
        screen == WearScreenId.availabilityInteraction;
  }
}
