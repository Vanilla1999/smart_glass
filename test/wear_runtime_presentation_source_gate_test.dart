import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('presentation model is immutable and scheduler boundary is typed', () {
    final String slice = File(
      'lib/modules/wear/runtime/wear_runtime_presentation_slice.dart',
    ).readAsStringSync();
    final String scheduler = File(
      'lib/modules/wear/runtime/wear_runtime_presentation_scheduler.dart',
    ).readAsStringSync();

    expect(slice, contains('_freezeClarificationArgs'));
    expect(slice, contains('List.unmodifiable(args.matches)'));
    expect(slice, contains('Set.unmodifiable(args.excludedWords)'));
    expect(slice, isNot(contains('final dynamic _authority')));
    expect(slice, isNot(contains('class WearRuntimePresentationScheduler')));
    expect(scheduler, contains('final WearRuntimeAuthority _authority'));
    expect(scheduler, contains('DateTime Function() _now'));
  });

  test('root wiring and epoch reset include aggregate presentation', () {
    final String authority = File(
      'lib/modules/wear/runtime/wear_runtime_authority_impl.dart',
    ).readAsStringSync();
    final String epoch = File(
      'lib/modules/wear/runtime/wear_runtime_feature_epoch_reducer.dart',
    ).readAsStringSync();

    expect(authority, contains('WearRuntimePresentationReducer()'));
    expect(
      authority.split('WearRuntimePresentationReducer()').length - 1,
      1,
    );
    expect(
      epoch.split('presentation: WearRuntimePresentationSlice()').length - 1,
      greaterThanOrEqualTo(3),
    );
  });

  test('projection defines aggregate clarification and status helpers', () {
    final String source = File(
      'lib/modules/wear/runtime/wear_runtime_projection.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('static WearGlassesPayload _genericStatus('),
    );
    expect(
      source,
      contains('static WearGlassesPayload _voiceClarification('),
    );
    expect(source, contains('WearRuntimePresentationSlice.from'));
    expect(source, contains('onPrepared: () {}'));
  });

  test('production facade dispatches typed presentation intents', () {
    final String source = File(
      'lib/modules/wear/application/wear_aggregate_presentation_flow_controller.dart',
    ).readAsStringSync();

    expect(source, contains('WearRuntimePresentationScheduler'));
    expect(source, contains('WearGenericStatusShown'));
    expect(source, contains('WearVoiceClarificationContextChanged'));
    expect(source, contains('WearVoiceClarificationFocusChanged'));
    expect(source, contains('WearVoiceClarificationNoticeChanged'));
  });

  test('temporary S12A workflows are absent from final tree', () {
    final Directory workflows = Directory('.github/workflows');
    if (!workflows.existsSync()) return;
    final Iterable<File> temporary = workflows
        .listSync()
        .whereType<File>()
        .where((File file) => file.path.contains('apply-wear-s12a'));
    expect(temporary, isEmpty);
  });
}
