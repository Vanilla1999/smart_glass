import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_group.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_availability_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_presentation_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_scan_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

VoiceDynamicItemsSnapshot selectWearDynamicVoiceItems(
  WearRuntimeState state,
  WearScreenId screen,
) {
  final WearAggregatePayload aggregate =
      state.payloadAs<WearAggregatePayload>();
  final WearRuntimeFeaturePayload features =
      aggregate.features as WearRuntimeFeaturePayload;
  final List<VoiceDynamicItem> items;
  Set<String> excludedWords = const <String>{};

  switch (screen) {
    case WearScreenId.printerSelect:
      items = features.printer.visiblePrinters
          .map((printer) => VoiceDynamicItem(
                id: printer.id,
                label: printer.name,
              ))
          .toList(growable: false);
    case WearScreenId.productSelect:
      final WearScanTaskSlice task = features.scan as WearScanTaskSlice;
      items = task.products
          .map((product) => VoiceDynamicItem(
                id: product.id.toString(),
                label: product.name,
              ))
          .toList(growable: false);
    case WearScreenId.availabilityGroup ||
          WearScreenId.availabilityProduct ||
          WearScreenId.availabilityDirectScan:
      final WearAvailabilityTaskSlice task =
          features.availability as WearAvailabilityTaskSlice;
      if (task.screen != screen) return VoiceDynamicItemsSnapshot.empty;
      items = task.listValues.map((Object value) {
        return switch (value) {
          WearAvailabilityGroup group => VoiceDynamicItem(
              id: group.id.toString(),
              label: group.name,
            ),
          WearAvailabilityProduct product => VoiceDynamicItem(
              id: product.id.toString(),
              label: product.name,
            ),
          _ => throw StateError('Unsupported availability voice item: $value'),
        };
      }).toList(growable: false);
    case WearScreenId.voiceClarification:
      final WearRuntimePresentationSlice presentation =
          WearRuntimePresentationSlice.from(aggregate.presentation);
      items =
          presentation.clarificationArgs?.matches ?? const <VoiceDynamicItem>[];
      excludedWords =
          presentation.clarificationArgs?.excludedWords ?? const <String>{};
    default:
      return VoiceDynamicItemsSnapshot.empty;
  }

  return VoiceDynamicItemsSnapshot(
    revision: Object.hashAll(
      items.map((VoiceDynamicItem item) => item.revisionHash),
    ),
    items: List<VoiceDynamicItem>.unmodifiable(items),
    excludedWords: Set<String>.unmodifiable(excludedWords),
  );
}
