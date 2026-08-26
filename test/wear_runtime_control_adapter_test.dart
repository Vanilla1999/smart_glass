import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_control_adapter.dart';
import 'package:smart_glasses/modules/wear/services/voice_state.dart';
import 'package:smart_glasses/modules/wear/services/wear_scanner_runtime_policy.dart';

void main() {
  AuthenticatedUser user() => AuthenticatedUser(
        idUser: 1,
        idEmployee: 2,
        name: 'Сотрудник',
      );

  test('legacy voice state maps to coarse aggregate phase', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    final WearRuntimeControlAdapter adapter =
        WearRuntimeControlAdapter(authority);
    addTearDown(authority.dispose);

    await adapter.observeVoiceState(
      const VoiceState(
        phase: VoicePhase.waitingForAudioRoute,
        captureEpoch: 2,
        attempt: 0,
        reason: 'test',
        lastTransitionAt: 1,
      ),
    );
    expect(authority.controls.voice.phase, WearVoiceRuntimePhase.starting);
    expect(authority.controls.voice.acceptsCommands, isFalse);

    await adapter.observeVoiceState(
      const VoiceState(
        phase: VoicePhase.ready,
        captureEpoch: 2,
        attempt: 0,
        reason: 'ready',
        lastTransitionAt: 2,
      ),
    );
    expect(authority.controls.voice.phase, WearVoiceRuntimePhase.ready);
    expect(authority.controls.voice.acceptsCommands, isTrue);
  });

  test('voice adapter reports aggregate command admission explicitly',
      () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    final WearRuntimeControlAdapter adapter =
        WearRuntimeControlAdapter(authority);
    addTearDown(authority.dispose);

    await adapter.observeVoiceState(
      const VoiceState(
        phase: VoicePhase.ready,
        captureEpoch: 1,
        attempt: 0,
        reason: 'ready-but-blocked',
        lastTransitionAt: 1,
      ),
      commandsEnabled: false,
    );

    expect(authority.controls.voice.phase, WearVoiceRuntimePhase.ready);
    expect(authority.controls.voice.commandsEnabled, isFalse);
    expect(authority.controls.voice.acceptsCommands, isFalse);
  });

  test('aggregate scanner selector preserves stabilized route semantics',
      () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    await authority.authorize(user());
    await authority.setRuntimeActive(true);
    final WearRuntimeControlAdapter adapter =
        WearRuntimeControlAdapter(authority);
    await adapter.observeScannerPrepared();
    await authority.observePhoneRouteAtEpoch(
      sessionEpoch: authority.state.sessionEpoch,
      screen: WearScreenId.menu,
      observationRevision: 1,
    );
    await authority.requestNavigation(WearScreenId.scanIdle);
    await authority.setPhoneUiActive(true);

    WearScannerRuntimeDecision aggregate = resolveWearScannerDecisionFromState(
      authority.state,
      currentScreenAcceptsBarcode: true,
    );
    expect(aggregate.hardwarePrepared, isFalse);
    expect(aggregate.barcodeAdmissionEnabled, isFalse);

    await authority.setPhoneUiActive(false);
    aggregate = resolveWearScannerDecisionFromState(
      authority.state,
      currentScreenAcceptsBarcode: true,
    );
    expect(aggregate.hardwarePrepared, isTrue);
    expect(aggregate.barcodeAdmissionEnabled, isTrue);

    await authority.observePhoneRouteAtEpoch(
      sessionEpoch: authority.state.sessionEpoch,
      screen: WearScreenId.scanIdle,
      observationRevision: 2,
    );
    aggregate = resolveWearScannerDecisionFromState(
      authority.state,
      currentScreenAcceptsBarcode: true,
    );
    expect(aggregate.hardwarePrepared, isTrue);
    expect(aggregate.barcodeAdmissionEnabled, isTrue);
  });

  test('terminal aggregate selector unconditionally closes scanner', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    await authority.authorize(user());
    await authority.terminate();

    final WearScannerRuntimeDecision decision =
        resolveWearScannerDecisionFromState(
      authority.state,
      currentScreenAcceptsBarcode: true,
    );

    expect(decision.hardwarePrepared, isFalse);
    expect(decision.barcodeAdmissionEnabled, isFalse);
  });

  test('adapter observation counters are monotonic', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    final WearRuntimeControlAdapter adapter =
        WearRuntimeControlAdapter(authority);
    addTearDown(authority.dispose);

    await adapter.observeConnectivity(WearConnectivityPhase.offline);
    final int first = authority.controls.connectivity.observationRevision;
    await adapter.observeConnectivity(WearConnectivityPhase.online);

    expect(authority.controls.connectivity.observationRevision, first + 1);
  });
}
