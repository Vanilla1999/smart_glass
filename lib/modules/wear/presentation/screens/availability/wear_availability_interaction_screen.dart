import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_scaling_list_view.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_projection.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearAvailabilityInteractionScreen extends StatefulWidget {
  const WearAvailabilityInteractionScreen({super.key});

  static const String route = '/wear_availability_interaction';

  @override
  State<WearAvailabilityInteractionScreen> createState() =>
      _WearAvailabilityInteractionScreenState();
}

class _WearAvailabilityInteractionScreenState
    extends State<WearAvailabilityInteractionScreen> {
  final ScrollController _scroll = ScrollController();
  final _flow = WearDependencies.I.wearFlowController;
  final _authority = WearDependencies.I.authority;
  StreamSubscription<WearRuntimeState>? _runtimeSub;
  int _focusedIndex = 0;
  static const int _itemCount = 2;

  @override
  void initState() {
    super.initState();
    _focusedIndex = _projectedFocus(_authority.state);
    _runtimeSub = _authority.states.listen(_onRuntimeState);
  }

  @override
  void dispose() {
    _runtimeSub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onRuntimeState(WearRuntimeState state) {
    final WearPhoneProjection projection =
        WearRuntimeProjection.projectPhone(state);
    if (projection.logicalScreen != WearScreenId.availabilityInteraction) {
      return;
    }
    final int next = projection.focusedIndex.clamp(0, _itemCount - 1);
    if (next == _focusedIndex) return;
    if (mounted) {
      setState(() => _focusedIndex = next);
    } else {
      _focusedIndex = next;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToFocused();
    });
  }

  int _projectedFocus(WearRuntimeState state) {
    final WearPhoneProjection projection =
        WearRuntimeProjection.projectPhone(state);
    if (projection.logicalScreen != WearScreenId.availabilityInteraction) {
      return 0;
    }
    return projection.focusedIndex.clamp(0, _itemCount - 1);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> items = <Widget>[
      Align(
        alignment: Alignment.topCenter,
        child: Text(
          'Тип взаимодействия',
          style: WearTypography.lable,
          textAlign: TextAlign.center,
        ),
      ),
      WearPill(
        title: 'Список',
        icon: WearImages.database,
        onTap: () => _flow.selectAvailabilityInteractionIndex(0),
      ),
      WearPill(
        title: 'Прямое сканирование',
        icon: WearImages.barcode,
        onTap: () => _flow.selectAvailabilityInteractionIndex(1),
      ),
      const SizedBox(height: 50),
    ];

    return WearScreenScaffold(
      showHomeButton: true,
      scrollController: _scroll,
      child: WearScalingListView(
        controller: _scroll,
        itemCount: items.length,
        itemExtent: 56,
        padding: const EdgeInsets.fromLTRB(0, 40, 0, 4.5),
        edgeFractionTop: 0.0,
        minScale: 0.68,
        minOpacity: 0.26,
        extraSideInset: 40,
        itemBuilder: (BuildContext context, int i) => items[i],
        onFocusChanged: (int listIndex) {
          final int itemIndex = (listIndex - 1).clamp(0, _itemCount - 1);
          if (itemIndex == _focusedIndex) return;
          _flow.setAvailabilityInteractionFocusedIndex(itemIndex);
        },
      ),
    );
  }

  void _scrollToFocused() {
    if (!_scroll.hasClients) return;
    final double target = ((_focusedIndex + 1) * 56.0).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }
}
