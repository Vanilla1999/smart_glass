import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';

void main() {
  test('authorization does not inherit anonymous control or printer state',
      () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    final int anonymousEpoch = authority.state.sessionEpoch;

    await authority.observeVoiceFromEpoch(
      sessionEpoch: anonymousEpoch,
      observationRevision: 1,
      phase: WearVoiceRuntimePhase.ready,
      commandsEnabled: true,
      captureEpoch: 1,
    );
    await authority.observeScannerHardwareFromEpoch(
      sessionEpoch: anonymousEpoch,
      observationRevision: 1,
      phase: WearScannerHardwarePhase.prepared,
    );

    await authority.authorize(
      AuthenticatedUser(idUser: 1, idEmployee: 2, name: 'User'),
    );

    expect(authority.state.sessionEpoch, anonymousEpoch + 1);
    expect(authority.controls.voice.acceptsCommands, isFalse);
    expect(
      authority.controls.scanner.hardwarePhase,
      WearScannerHardwarePhase.released,
    );
    expect(authority.printerTask.selection, isNull);
    expect(authority.printerTask.printers, isEmpty);
  });
}
