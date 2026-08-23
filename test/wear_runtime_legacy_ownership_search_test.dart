import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production Wear runtime has no retired writable owners', () {
    final List<File> files = Directory('lib/modules/wear')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File file) => file.path.endsWith('.dart'))
        .toList(growable: false);
    final String source =
        files.map((File file) => file.readAsStringSync()).join();

    for (final String forbidden in <String>[
      'class WearSession {',
      'WearSession.',
      'WearActualScreenStore',
      'actualScreenStore',
      'configureIdentityAuthority',
      'beginNewIdentityRuntime',
      '_screenPayloads',
      'FlutterWearGlassesOutput',
      'wear_runtime_store_payload_impl.dart',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('status reporter does not transport glasses projections', () {
    final String source = File(
      'lib/modules/wear/services/wear_status_icon_reporter.dart',
    ).readAsStringSync();

    for (final String forbidden in <String>[
      'wearGlassesBridge',
      '.show(',
      '.update(',
      'sendFast(',
      'sendTransientFast(',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('exactly one WearRuntimeStore implementation remains', () {
    final List<File> implementations = Directory('lib/modules/wear/runtime')
        .listSync()
        .whereType<File>()
        .where((File file) => file.path.endsWith('.dart'))
        .where((File file) => file.readAsStringSync().contains(
              'class WearRuntimeStore {',
            ))
        .toList(growable: false);

    expect(implementations, hasLength(1));
  });

  test('migrated widgets do not enter business screens', () {
    final String source = Directory('lib/modules/wear/presentation')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File file) => file.path.endsWith('.dart'))
        .map((File file) => file.readAsStringSync())
        .join();

    for (final String screen in <String>[
      'scanIdle',
      'productSelect',
      'printerSelect',
      'availabilityGroup',
      'availabilityProduct',
      'availabilityDirectScan',
      'availabilityCheck',
      'availabilityFill',
    ]) {
      expect(
        source,
        isNot(contains('enterScreen(WearScreenId.$screen')),
        reason: screen,
      );
    }
  });
}
