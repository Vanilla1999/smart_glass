import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_screen_ownership_registry.dart';

void main() {
  test('registry exposes immutable unique ownership', () {
    final WearScreenOwnershipRegistry registry = WearScreenOwnershipRegistry(
      <String, Iterable<WearScreenId>>{
        'printer': <WearScreenId>{WearScreenId.printerSelect},
        'scan': <WearScreenId>{
          WearScreenId.scanIdle,
          WearScreenId.productSelect,
        },
      },
    );

    expect(registry.ownerOf(WearScreenId.printerSelect), 'printer');
    expect(registry.ownerOf(WearScreenId.scanIdle), 'scan');
    expect(registry.ownerOf(WearScreenId.menu), isNull);
    expect(
      () => registry.owners[WearScreenId.menu] = 'menu',
      throwsUnsupportedError,
    );
  });

  test('duplicate logical screen ownership fails during construction', () {
    expect(
      () => WearScreenOwnershipRegistry(
        <String, Iterable<WearScreenId>>{
          'first': <WearScreenId>{WearScreenId.availabilityProduct},
          'second': <WearScreenId>{WearScreenId.availabilityProduct},
        },
      ),
      throwsStateError,
    );
  });

  test('empty owner id is rejected', () {
    expect(
      () => WearScreenOwnershipRegistry(
        <String, Iterable<WearScreenId>>{
          ' ': <WearScreenId>{WearScreenId.menu},
        },
      ),
      throwsArgumentError,
    );
  });
}
