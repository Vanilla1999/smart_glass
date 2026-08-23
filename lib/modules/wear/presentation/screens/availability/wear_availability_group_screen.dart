import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smart_glasses/modules/wear/application/wear_availability_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_group.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_loading.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_scaling_list_view.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearAvailabilityGroupScreen extends StatefulWidget {
  const WearAvailabilityGroupScreen({super.key});
  static const String route = '/wear_availability_groups';

  @override
  State<WearAvailabilityGroupScreen> createState() => _State();
}

class _State extends State<WearAvailabilityGroupScreen> {
  final ScrollController _scroll = ScrollController();
  late final WearFlowController _flow = WearDependencies.I.wearFlowController;
  late final StreamSubscription<WearAvailabilityRuntimeState> _subscription;
  late WearAvailabilityRuntimeState _state;

  @override
  void initState() {
    super.initState();
    _state = _flow.availabilityState;
    _subscription = _flow.availabilityStateStream.listen((next) {
      final int previous = _state.focusedIndex;
      if (mounted) setState(() => _state = next);
      if (previous != next.focusedIndex) _scrollTo(next.focusedIndex);
    });
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_state.busy) {
      return const WearScreenScaffold(
        showHomeButton: true,
        child: Center(child: WearLoading()),
      );
    }
    final List<WearAvailabilityGroup> groups = _state.groups;
    return WearScreenScaffold(
      showHomeButton: true,
      scrollController: _scroll,
      child: groups.isEmpty
          ? Center(child: Text(_state.error ?? 'Нет заданий доступности'))
          : WearScalingListView(
              controller: _scroll,
              itemCount: groups.length + 2,
              itemExtent: 56,
              padding: const EdgeInsets.fromLTRB(0, 40, 0, 4.5),
              itemBuilder: (_, int index) {
                if (index == 0) {
                  return Align(
                    alignment: Alignment.topCenter,
                    child: Text('Доступность', style: WearTypography.lable),
                  );
                }
                if (index == groups.length + 1) return const SizedBox.shrink();
                final WearAvailabilityGroup group = groups[index - 1];
                return WearPill(
                  title: group.name,
                  subtitle: 'ТП: ${group.counter}',
                  icon: WearImages.database,
                  onTap: () => _flow.selectAvailabilityItem(group),
                );
              },
              onFocusChanged: (int index) => _flow.focusAvailabilityItem(
                  (index - 1).clamp(0, groups.length - 1)),
            ),
    );
  }

  void _scrollTo(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        (index * 56.0).clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }
}
