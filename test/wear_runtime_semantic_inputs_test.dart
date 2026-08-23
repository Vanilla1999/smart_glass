import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/presentation/input/wear_ui_effect_consumer.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

void main() {
  group('unified semantic inputs', () {
    for (final WearInputModality modality in <WearInputModality>[
      WearInputModality.touch,
      WearInputModality.voice,
      WearInputModality.button,
    ]) {
      test('${modality.name} creates the same authoritative focus', () async {
        final WearRuntimeAuthority authority = WearRuntimeAuthority(
          initialScreen: WearScreenId.menu,
        );
        addTearDown(authority.dispose);

        final WearDispatchResult receipt = await authority.dispatchSemanticInput(
          kind: WearSemanticInputKind.presentationFocus,
          modality: modality,
          expectedScreen: WearScreenId.menu,
          focusIndex: 2,
        );

        expect(receipt.accepted, isTrue);
        expect(
          (authority.payload.presentation as WearPresentationFocusSlice)
              .focusFor(WearScreenId.menu),
          2,
        );
      });
    }

    test('unchanged focus is accepted without a revision', () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.homeConfirm,
      );
      addTearDown(authority.dispose);
      await authority.dispatchSemanticInput(
        kind: WearSemanticInputKind.presentationFocus,
        modality: WearInputModality.touch,
        expectedScreen: WearScreenId.homeConfirm,
        focusIndex: 1,
      );
      final int revision = authority.state.revision;

      final WearDispatchResult receipt = await authority.dispatchSemanticInput(
        kind: WearSemanticInputKind.presentationFocus,
        modality: WearInputModality.voice,
        expectedScreen: WearScreenId.homeConfirm,
        focusIndex: 1,
      );

      expect(receipt.accepted, isTrue);
      expect(receipt.stateChanged, isFalse);
      expect(authority.state.revision, revision);
    });

    test('focus from an old logical screen is rejected without mutation',
        () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.continueScan,
      );
      addTearDown(authority.dispose);
      final int revision = authority.state.revision;

      final WearDispatchResult receipt = await authority.dispatchSemanticInput(
        kind: WearSemanticInputKind.presentationFocus,
        modality: WearInputModality.button,
        expectedScreen: WearScreenId.menu,
        focusIndex: 1,
      );

      expect(receipt.rejectReason, WearDispatchRejectReason.staleScreen);
      expect(authority.state.revision, revision);
    });

    test('focus from an old session epoch is rejected without mutation',
        () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.availabilityInteraction,
      );
      addTearDown(authority.dispose);
      final int revision = authority.state.revision;

      final WearDispatchResult receipt = await authority.dispatchSemanticInput(
        kind: WearSemanticInputKind.presentationFocus,
        modality: WearInputModality.touch,
        expectedScreen: WearScreenId.availabilityInteraction,
        expectedSessionEpoch: authority.state.sessionEpoch + 1,
        focusIndex: 1,
      );

      expect(receipt.rejectReason, WearDispatchRejectReason.staleEpoch);
      expect(authority.state.revision, revision);
    });

    for (final WearInputModality modality in WearInputModality.values) {
      test('${modality.name} creates the same manual-input request', () async {
        final WearRuntimeAuthority authority = WearRuntimeAuthority(
          initialScreen: WearScreenId.availabilityDirectScan,
        );
        addTearDown(authority.dispose);

        final WearDispatchResult receipt = await authority.dispatchSemanticInput(
          kind: WearSemanticInputKind.requestUiEffect,
          modality: modality,
          expectedScreen: WearScreenId.availabilityDirectScan,
          uiEffectKind: WearUiEffectKind.manualBarcodeInput,
        );

        expect(receipt.accepted, isTrue);
        final WearUiEffect effect = authority.payload.uiEffects.effects.single;
        expect(effect.kind, WearUiEffectKind.manualBarcodeInput);
        expect(effect.expectedScreen, WearScreenId.availabilityDirectScan);
        expect(effect.status, WearUiEffectStatus.pending);
      });
    }

    test('old logical screen input is rejected without mutation', () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.scanIdle,
      );
      addTearDown(authority.dispose);
      final int revision = authority.state.revision;

      final WearDispatchResult receipt = await authority.dispatchSemanticInput(
        kind: WearSemanticInputKind.requestUiEffect,
        modality: WearInputModality.voice,
        expectedScreen: WearScreenId.availabilityDirectScan,
        uiEffectKind: WearUiEffectKind.manualBarcodeInput,
      );

      expect(receipt.rejectReason, WearDispatchRejectReason.staleScreen);
      expect(authority.state.revision, revision);
    });

    test('barcode has one semantic path into the scan reducer', () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.scanIdle,
      );
      addTearDown(authority.dispose);
      await authority.enterScanScreen(WearScreenId.scanIdle);

      final WearDispatchResult receipt = await authority.dispatchSemanticInput(
        kind: WearSemanticInputKind.barcode,
        modality: WearInputModality.barcode,
        expectedScreen: WearScreenId.scanIdle,
        value: '4600000000000',
      );

      expect(receipt.accepted, isTrue);
      expect(receipt.scheduledEffectCount, 1);
      expect(authority.scanTask.barcode, '4600000000000');
      expect(
        authority.state.expectedOperationId(WearLookupBarcodeEffect.operationKind),
        isNotNull,
      );
    });

    test('serialized queue preserves semantic request order', () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.settings,
      );
      addTearDown(authority.dispose);

      await Future.wait(<Future<WearDispatchResult>>[
        authority.dispatchSemanticInput(
          kind: WearSemanticInputKind.requestUiEffect,
          modality: WearInputModality.touch,
          expectedScreen: WearScreenId.settings,
          uiEffectKind: WearUiEffectKind.systemWifiSettings,
        ),
        authority.dispatchSemanticInput(
          kind: WearSemanticInputKind.requestUiEffect,
          modality: WearInputModality.voice,
          expectedScreen: WearScreenId.settings,
          uiEffectKind: WearUiEffectKind.confirmationDialog,
        ),
      ]);

      expect(
        authority.payload.uiEffects.effects
            .map((WearUiEffect effect) => effect.kind),
        <WearUiEffectKind>[
          WearUiEffectKind.systemWifiSettings,
          WearUiEffectKind.confirmationDialog,
        ],
      );
    });
  });

  group('bounded UI effects', () {
    test('rebuild and reconnect observe one stable pending identity', () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.settings,
      );
      addTearDown(authority.dispose);
      await _requestWifi(authority);
      final WearUiEffect original = authority.payload.uiEffects.effects.single;

      final WearUiEffect rebuilt = authority.payload.uiEffects.effects.single;
      final WearUiEffect reconnected = (await authority.states.first)
          .payloadAs<WearAggregatePayload>()
          .uiEffects
          .effects
          .single;

      expect(rebuilt.effectId, original.effectId);
      expect(reconnected.effectId, original.effectId);
      expect(authority.payload.uiEffects.effects, hasLength(1));
    });

    test('claim is exactly once and acknowledgement removes atomically', () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.settings,
      );
      addTearDown(authority.dispose);
      await _requestWifi(authority);
      final WearUiEffect effect = authority.payload.uiEffects.effects.single;

      final WearDispatchResult first = await authority.claimUiEffect(effect);
      final WearDispatchResult rebuild = await authority.claimUiEffect(effect);
      expect(first.stateChanged, isTrue);
      expect(rebuild.stateChanged, isFalse);
      expect(authority.payload.uiEffects.effects.single.status,
          WearUiEffectStatus.claimed);

      final WearDispatchResult completed =
          await authority.completeUiEffect(effect);
      expect(completed.accepted, isTrue);
      expect(authority.payload.uiEffects.effects, isEmpty);
    });

    test('one-per-kind bound rejects duplicate but permits other kind', () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.settings,
      );
      addTearDown(authority.dispose);
      await _requestWifi(authority);

      final WearDispatchResult duplicate = await _requestWifi(authority);
      final WearDispatchResult other = await authority.dispatchSemanticInput(
        kind: WearSemanticInputKind.requestUiEffect,
        modality: WearInputModality.touch,
        expectedScreen: WearScreenId.settings,
        uiEffectKind: WearUiEffectKind.confirmationDialog,
      );

      expect(duplicate.rejectReason, WearDispatchRejectReason.duplicate);
      expect(other.accepted, isTrue);
      expect(authority.payload.uiEffects.effects, hasLength(2));
    });

    test('stale completion cannot remove a newer effect', () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.settings,
      );
      addTearDown(authority.dispose);
      await _requestWifi(authority);
      final WearUiEffect old = authority.payload.uiEffects.effects.single;
      await authority.cancelUiEffect(old);
      await _requestWifi(authority);

      final WearDispatchResult stale = await authority.completeUiEffect(old);

      expect(stale.rejectReason, WearDispatchRejectReason.staleOperation);
      expect(authority.payload.uiEffects.effects.single.effectId,
          isNot(old.effectId));
    });

    test('completion from an old logical screen is rejected', () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.settings,
      );
      addTearDown(authority.dispose);
      await _requestWifi(authority);
      final WearUiEffect old = authority.payload.uiEffects.effects.single;
      await authority.requestNavigation(WearScreenId.menu);

      final WearDispatchResult stale = await authority.completeUiEffect(old);

      expect(stale.rejectReason, WearDispatchRejectReason.staleScreen);
      expect(authority.payload.uiEffects.effects, hasLength(1));
    });

    test('stale epoch result is rejected while current effect remains', () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.settings,
      );
      addTearDown(authority.dispose);
      await _requestWifi(authority);
      final WearUiEffect old = authority.payload.uiEffects.effects.single;

      final WearDispatchResult stale = await authority.store.dispatch(
        WearUiEffectCompleted(
          effectId: old.effectId,
          sessionEpoch: old.sessionEpoch + 1,
          expectedScreen: old.expectedScreen,
        ),
      );

      expect(authority.payload.uiEffects.effects, hasLength(1));
      expect(stale.rejectReason, WearDispatchRejectReason.staleEpoch);
    });

    test('terminal epoch reset clears pending effects', () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.settings,
      );
      await _requestWifi(authority);

      await authority.terminate();

      expect(authority.payload.uiEffects.effects, isEmpty);
    });

    test('inactive phone explicitly defers the pending effect', () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.settings,
      );
      addTearDown(authority.dispose);
      await authority.setPhoneUiActive(false);

      await _requestWifi(authority);
      final WearUiEffect effect = authority.payload.uiEffects.effects.single;

      final WearDispatchResult claim = await authority.claimUiEffect(effect);

      expect(WearUiEffectSlice.inactivePhonePolicy,
          WearInactivePhoneUiPolicy.defer);
      expect(claim.rejectReason, WearDispatchRejectReason.busy);
      expect(authority.payload.uiEffects.effects.single.status,
          WearUiEffectStatus.pending);
    });

    test('inactive pending effect is claimed once when phone resumes', () async {
      final WearRuntimeAuthority authority = WearRuntimeAuthority(
        initialScreen: WearScreenId.availabilityDirectScan,
      );
      addTearDown(authority.dispose);
      await authority.setPhoneUiActive(false);
      final List<WearUiEffect> executed = <WearUiEffect>[];
      final Completer<void> execution = Completer<void>();
      Future<void> execute(WearUiEffect effect) async {
        executed.add(effect);
        if (!execution.isCompleted) execution.complete();
      }

      final WearUiEffectConsumer first = WearUiEffectConsumer(
        authority: authority,
        kind: WearUiEffectKind.manualBarcodeInput,
        expectedScreen: WearScreenId.availabilityDirectScan,
        execute: execute,
      );
      final WearUiEffectConsumer rebuilt = WearUiEffectConsumer(
        authority: authority,
        kind: WearUiEffectKind.manualBarcodeInput,
        expectedScreen: WearScreenId.availabilityDirectScan,
        execute: execute,
      );
      addTearDown(first.dispose);
      addTearDown(rebuilt.dispose);

      await first.request();
      final WearUiEffect pending = authority.payload.uiEffects.effects.single;
      expect(pending.status, WearUiEffectStatus.pending);

      await authority.setPhoneUiActive(true);
      await execution.future;

      expect(executed, hasLength(1));
      expect(executed.single.effectId, pending.effectId);
      expect(authority.payload.uiEffects.effects.single.status,
          WearUiEffectStatus.claimed);
    });
  });
}

Future<WearDispatchResult> _requestWifi(WearRuntimeAuthority authority) {
  return authority.dispatchSemanticInput(
    kind: WearSemanticInputKind.requestUiEffect,
    modality: WearInputModality.touch,
    expectedScreen: WearScreenId.settings,
    uiEffectKind: WearUiEffectKind.systemWifiSettings,
  );
}
