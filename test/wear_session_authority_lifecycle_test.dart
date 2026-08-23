import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';

void main() {
  test('ordinary getter does not revive a terminal lazy authority', () async {
    final WearRuntimeAuthority original = WearSession.identityAuthority;
    await original.terminate();

    expect(WearSession.identityAuthority, same(original));
    expect(WearSession.identityAuthority.state.terminal, isTrue);

    final WearRuntimeAuthority renewed = WearSession.beginNewIdentityRuntime();
    expect(renewed, isNot(same(original)));
    expect(renewed.state.terminal, isFalse);
    await renewed.dispose();
  });
}
