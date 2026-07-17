import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:smart_glasses/modules/wear/application/wear_flow_state.dart';
import 'package:smart_glasses/modules/wear/infrastructure/screen_lifecycle_logging.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/photo/wear_latest_photo_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_scaling_list_view.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearMenuScreen extends StatefulWidget {
  const WearMenuScreen({super.key});

  static const String route = '/wear_menu';

  @override
  State<WearMenuScreen> createState() => _WearMenuScreenState();
}

class _WearMenuScreenState extends State<WearMenuScreen>
    with ScreenLifecycleLogging<WearMenuScreen> {
  final ScrollController _scroll = ScrollController();
  final _flow = WearDependencies.I.wearFlowController;
  StreamSubscription<WearFlowState>? _flowSub;
  int _focusedIndex = 0;
  static const int _menuItemCount = 4;

  @override
  void initState() {
    super.initState();
    _focusedIndex = _flow.state.menuFocusedIndex;
    _flow.enterScreen(WearScreenId.menu);
    _flowSub = _flow.stateStream.listen(_onFlowState);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToFocusedIndex(_focusedIndex, animate: false);
    });
  }

  @override
  void dispose() {
    _flowSub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onFlowState(WearFlowState state) {
    if (state.screen != WearScreenId.menu) return;
    final int next = state.menuFocusedIndex.clamp(0, _menuItemCount - 1);
    if (next == _focusedIndex) return;
    if (mounted) {
      setState(() => _focusedIndex = next);
    } else {
      _focusedIndex = next;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToFocusedIndex(next);
    });
  }

  String _getMenuItemName(int index) {
    switch (index) {
      case 0:
        return 'Печать ценника';
      case 1:
        return 'Доступность';
      case 2:
        return 'Справка';
      case 3:
        return 'Настройки';
      default:
        return 'UNKNOWN(index=$index)';
    }
  }

  void _scrollToFocusedIndex(int index, {bool animate = true}) {
    if (!_scroll.hasClients) return;
    final int listIndex = index < 2 ? index + 1 : index + 2;
    final double target = (listIndex * 56.0).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    if (animate) {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    } else {
      _scroll.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> items = <Widget>[
      Align(
        alignment: Alignment.topCenter,
        child: Text(
          'Меню',
          style: WearTypography.lable15,
          textAlign: TextAlign.center,
        ),
      ),
      WearPill(
        title: 'Печать ценника',
        onTap: () => _flow.selectMenuIndex(0),
      ),
      WearPill(
        title: 'Доступность',
        onTap: () => _flow.selectMenuIndex(1),
      ),
      WearPill(
        title: 'Последнее фото',
        onTap: () => context.push(WearLatestPhotoScreen.route),
      ),
      WearPill(
        title: 'Справка',
        onTap: () => _flow.selectMenuIndex(2),
      ),
      WearPill(
        title: 'Настройки',
        icon: WearImages.gear,
        onTap: () => _flow.selectMenuIndex(3),
      ),
      const SizedBox(
        height: 50,
      )
    ];

    return WearScreenScaffold(
      scrollController: _scroll,
      child: WearScalingListView(
        controller: _scroll,
        itemCount: items.length,
        itemExtent: 56,
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 4.5),
        edgeFractionTop: 0.06,
        edgeFractionBottom: 0.14,
        minScale: 0.72,
        minOpacity: 0.30,
        baseSideInset: 10,
        extraSideInset: 30,
        itemBuilder: (BuildContext context, int i) => items[i],
        onFocusChanged: (int listIndex) {
          final int? itemIndex = switch (listIndex) {
            1 => 0,
            2 => 1,
            4 => 2,
            5 => 3,
            _ => null,
          };
          if (itemIndex == null) return;
          print(
            '[MenuScreen] onFocusChanged: itemIndex=$itemIndex => ${_getMenuItemName(itemIndex)}',
          );
          if (_focusedIndex != itemIndex) {
            setState(() => _focusedIndex = itemIndex);
          }
          _flow.setMenuFocusedIndex(itemIndex);
        },
      ),
    );
  }
}
