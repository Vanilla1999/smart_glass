import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_group.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_availability_glasses_payloads.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/cubit/wear_availability_list_providers.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_product_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_loading.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_scaling_list_view.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/services/wear_status_icon_reporter.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearAvailabilityGroupScreen extends ConsumerStatefulWidget {
  const WearAvailabilityGroupScreen({super.key});

  static const String route = '/wear_availability_groups';

  @override
  ConsumerState<WearAvailabilityGroupScreen> createState() =>
      _WearAvailabilityGroupScreenState();
}

class _WearAvailabilityGroupScreenState
    extends ConsumerState<WearAvailabilityGroupScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<WearAvailabilityGroup>> groups =
        ref.watch(wearAvailabilityGroupsProvider);
    groups.whenData(_sendGlassesState);

    return WearScreenScaffold(
      showHomeButton: true,
      scrollController: _scroll,
      child: groups.when(
        data: _buildGroups,
        loading: () {
          _sendLoading();
          return const Center(child: WearLoading());
        },
        error: (Object error, StackTrace _) {
          _sendError(error);
          return _buildMessage('Ошибка загрузки\n${_asUiMessage(error)}');
        },
      ),
    );
  }

  Widget _buildGroups(List<WearAvailabilityGroup> groups) {
    if (groups.isEmpty) {
      return _buildMessage('Нет заданий доступности');
    }

    return RefreshIndicator(
      onRefresh: () => ref.refresh(wearAvailabilityGroupsProvider.future),
      child: WearScalingListView(
        controller: _scroll,
        itemCount: groups.length + 2,
        itemExtent: 56,
        padding: const EdgeInsets.fromLTRB(0, 40, 0, 4.5),
        edgeFractionTop: 0.0,
        minScale: 0.68,
        minOpacity: 0.26,
        extraSideInset: 40,
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        itemBuilder: (BuildContext context, int i) {
          if (i == 0) {
            return Align(
              alignment: Alignment.topCenter,
              child: Text(
                'Доступность',
                style: WearTypography.lable,
                textAlign: TextAlign.center,
              ),
            );
          }
          if (i == groups.length + 1) {
            return const SizedBox.shrink();
          }

          final WearAvailabilityGroup group = groups[i - 1];
          return WearPill(
            title: group.name,
            subtitle: 'ТП: ${group.counter}',
            icon: WearImages.database,
            onTap: () => context.push(
              WearAvailabilityProductScreen.route,
              extra: group,
            ),
          );
        },
      ),
    );
  }

  Widget _buildMessage(String message) {
    return Center(
      child: Text(
        message,
        style: WearTypography.lable,
        textAlign: TextAlign.center,
      ),
    );
  }

  void _sendGlassesState(List<WearAvailabilityGroup> groups) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WearStatusIconReporter.I.send(
        WearAvailabilityGlassesPayloads.groups(groups),
      );
    });
  }

  void _sendLoading() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WearStatusIconReporter.I.send(
        WearAvailabilityGlassesPayloads.loading(
          title: 'Доступность',
          statusText: 'Загружаем...',
          statusIcon: WearImages.database,
        ),
      );
    });
  }

  void _sendError(Object error) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WearStatusIconReporter.I.send(
        WearAvailabilityGlassesPayloads.error(
          title: 'Ошибка доступности',
          message: _asUiMessage(error),
        ),
      );
    });
  }

  String _asUiMessage(Object error) {
    final String raw = error.toString();
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length);
    }
    return raw;
  }
}
