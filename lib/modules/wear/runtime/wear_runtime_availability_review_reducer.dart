import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_group.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_availability_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

class WearReviewedAvailabilitySliceReducer implements WearSliceReducer {
  const WearReviewedAvailabilitySliceReducer();

  static const WearAvailabilitySliceReducer _base =
      WearAvailabilitySliceReducer();

  @override
  WearReduction? reduceSlice(WearRuntimeState state, WearIntent intent) {
    final WearAggregatePayload aggregate =
        state.payloadAs<WearAggregatePayload>();
    final WearFeaturePayload rawFeatures = aggregate.features;
    if (rawFeatures is! WearRuntimeFeaturePayload ||
        rawFeatures.availability is! WearAvailabilityTaskSlice) {
      return null;
    }
    final WearAvailabilityTaskSlice task =
        rawFeatures.availability as WearAvailabilityTaskSlice;

    if (intent is WearAvailabilityEntered) {
      final bool sameScreen = task.screen == intent.screen &&
          aggregate.navigation.logicalScreen == intent.screen;
      if (sameScreen) {
        if (task.isBusy) return WearReduction.accept();
        if (!_entryRequiresBusinessWork(task, intent)) {
          return WearReduction.accept();
        }
      }
      final WearRuntimeState input = sameScreen
          ? state
          : state.clearExpectedOperationPrefix('availability.');
      return _postProcess(_base.reduceSlice(input, intent), intent);
    }

    if (intent is WearAvailabilityOperationSucceeded ||
        intent is WearAvailabilityOperationFailed) {
      final WearAvailabilityOperation operation =
          intent is WearAvailabilityOperationSucceeded
              ? intent.operation
              : (intent as WearAvailabilityOperationFailed).operation;
      if (operation != WearAvailabilityOperation.navigate &&
          task.screen != aggregate.navigation.logicalScreen) {
        return WearReduction.reject(WearDispatchRejectReason.staleScreen);
      }
    }

    return _postProcess(_base.reduceSlice(state, intent), intent);
  }

  bool _entryRequiresBusinessWork(
    WearAvailabilityTaskSlice task,
    WearAvailabilityEntered intent,
  ) {
    if (intent.screen == WearScreenId.availabilityGroup) {
      return task.flow.groups.isEmpty;
    }
    if (intent.screen == WearScreenId.availabilityProduct &&
        intent.extra is WearAvailabilityGroup) {
      final WearAvailabilityGroup group = intent.extra as WearAvailabilityGroup;
      return task.flow.selectedGroup?.id != group.id ||
          task.flow.products.isEmpty;
    }
    if (intent.screen == WearScreenId.availabilityCheck &&
        intent.extra is WearAvailabilityProduct) {
      return task.flow.selectedProduct?.id !=
          (intent.extra as WearAvailabilityProduct).id;
    }
    return false;
  }

  WearReduction? _postProcess(
    WearReduction? reduction,
    WearIntent intent,
  ) {
    if (reduction == null ||
        !reduction.accepted ||
        reduction.nextState == null ||
        intent is! WearAvailabilityOperationSucceeded) {
      return reduction;
    }
    if (intent.operation != WearAvailabilityOperation.start &&
        intent.operation != WearAvailabilityOperation.selectGroup &&
        intent.operation != WearAvailabilityOperation.selectProduct &&
        intent.operation != WearAvailabilityOperation.selectScannedProduct &&
        intent.operation != WearAvailabilityOperation.findBarcode &&
        intent.operation != WearAvailabilityOperation.complete) {
      return reduction;
    }

    final WearRuntimeState nextState = reduction.nextState!;
    final WearAggregatePayload aggregate =
        nextState.payloadAs<WearAggregatePayload>();
    final WearRuntimeFeaturePayload features =
        aggregate.features as WearRuntimeFeaturePayload;
    final WearAvailabilityTaskSlice task =
        features.availability as WearAvailabilityTaskSlice;
    final WearRuntimeState focused = nextState.withPayload(
      aggregate.copyWith(
        features: features.copyWith(
          availability: task.copyWith(focusedIndex: 0),
        ),
      ),
    );
    return WearReduction.accept(
      nextState: focused,
      effects: reduction.effects,
    );
  }
}
