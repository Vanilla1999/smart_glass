import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_control_adapter.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';
import 'package:smart_glasses/modules/wear/services/voice_state.dart';

void main() {
  test('adapter callback from cleared session is stale by epoch', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    await authority.authorize(
      AuthenticatedUser(idUser: 1, idEmployee: 2, name: 'Сотрудник'),
    );
    final WearRuntimeControlAdapter oldAdapter =
        WearRuntimeControlAdapter(authority);
    final int oldEpoch = oldAdapter.sessionEpoch;

    await authority.clearSession();
    final WearDispatchResult stale = await oldAdapter.observeVoiceState(
      const VoiceState(
        phase: VoicePhase.ready,
        captureEpoch: 1,
        attempt: 0,
        reason: 'late',
        lastTransitionAt: 1,
      ),
    );

    expect(authority.state.sessionEpoch, oldEpoch + 1);
    expect(stale.accepted, isFalse);
    expect(stale.rejectReason, WearDispatchRejectReason.staleEpoch);
    expect(authority.controls.voice.acceptsCommands, isFalse);
  });

  test('new adapter starts from current observation revisions', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    final WearRuntimeControlAdapter first =
        WearRuntimeControlAdapter(authority);
    await first.observeConnectivity(WearConnectivityPhase.offline);
    final int revision = authority.controls.connectivity.observationRevision;

    final WearRuntimeControlAdapter second =
        WearRuntimeControlAdapter(authority);
    final WearDispatchResult result =
        await second.observeConnectivity(WearConnectivityPhase.online);

    expect(result.accepted, isTrue);
    expect(authority.controls.connectivity.observationRevision, revision + 1);
  });
}
