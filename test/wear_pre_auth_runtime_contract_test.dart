import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

void main() {
  test('pre-auth main may activate runtime for badge scanning', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority(
      initialScreen: WearScreenId.main,
    );
    addTearDown(authority.dispose);

    final WearDispatchResult receipt =
        await authority.setRuntimeActive(true);

    expect(receipt.accepted, isTrue);
    expect(authority.payload.lifecycle.runtimeActive, isTrue);
    expect(authority.isAuthorized, isFalse);
  });

  test('other anonymous logical screens remain unable to activate runtime',
      () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority(
      initialScreen: WearScreenId.scannerConnect,
    );
    addTearDown(authority.dispose);

    final WearDispatchResult receipt =
        await authority.setRuntimeActive(true);

    expect(receipt.accepted, isFalse);
    expect(receipt.rejectReason, WearDispatchRejectReason.unsupported);
    expect(authority.payload.lifecycle.runtimeActive, isFalse);
  });
}
