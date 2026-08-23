import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';

void main() {
  test('authorization does not inherit anonymous voice or scanner admission',
      () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);

    await authority.observeVoice(
      observationRevision: 1,
      phase: WearVoiceRuntimePhase.ready,
      commandsEnabled: true,
      captureEpoch: 1,
    );
    await authority.observeScannerHardware(
      observationRevision: 1,
      phase: WearScannerHardwarePhase.prepared,
    );
    expect(authority.controls.voice.acceptsCommands, isTrue);
    expect(authority.controls.scanner.hardwarePrepared, isTrue);
    final int oldEpoch = authority.state.sessionEpoch;

    await authority.authorize(
      AuthenticatedUser(idUser: 1, idEmployee: 2, name: 'User'),
    );

    expect(authority.state.sessionEpoch, oldEpoch + 1);
    expect(authority.controls.voice.phase, WearVoiceRuntimePhase.disabled);
    expect(authority.controls.voice.commandsEnabled, isFalse);
    expect(
      authority.controls.scanner.hardwarePhase,
      WearScannerHardwarePhase.released,
    );
    expect(authority.controls.scanner.barcodeAdmissionEnabled, isFalse);
  });
}
