import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_group.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';

final AutoDisposeFutureProvider<List<WearAvailabilityGroup>>
    wearAvailabilityGroupsProvider =
    FutureProvider.autoDispose<List<WearAvailabilityGroup>>(
  (Ref ref) async {
    final state = await WearDependencies.I.availabilityFlowUseCase.start();
    return state.groups;
  },
);

final AutoDisposeFutureProviderFamily<List<WearAvailabilityProduct>,
        WearAvailabilityGroup> wearAvailabilityProductsProvider =
    FutureProvider.autoDispose
        .family<List<WearAvailabilityProduct>, WearAvailabilityGroup>(
  (Ref ref, WearAvailabilityGroup group) {
    return WearDependencies.I.availabilityRepository
        .getProductsByGroup(group.id);
  },
);
