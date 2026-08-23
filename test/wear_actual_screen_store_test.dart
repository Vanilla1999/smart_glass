import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_actual_screen_store.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';

void main() {
  test('actual route acknowledgement increments revision once', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    final WearActualScreenStore store = WearActualScreenStore(authority);

    expect(await store.confirm(WearScreenId.menu), isTrue);
    expect(store.screen, WearScreenId.menu);
    expect(store.revision, 1);
    expect(await store.confirm(WearScreenId.menu), isFalse);
    expect(store.revision, 1);
    expect(await store.confirm(WearScreenId.availabilityInteraction), isTrue);
    expect(store.revision, 2);
  });

  test('T09 one hundred route confirmations remain monotonic', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority();
    addTearDown(authority.dispose);
    final WearActualScreenStore store = WearActualScreenStore(authority);
    for (int index = 0; index < 100; index++) {
      await store.confirm(index.isEven ? WearScreenId.menu : WearScreenId.help);
    }

    expect(store.revision, 100);
    expect(store.screen, WearScreenId.help);
  });
}
