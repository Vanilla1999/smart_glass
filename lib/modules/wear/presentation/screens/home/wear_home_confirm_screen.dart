import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_state.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/infrastructure/screen_lifecycle_logging.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/menu/wear_menu_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearHomeConfirmScreen extends StatefulWidget {
  const WearHomeConfirmScreen({super.key});

  static const String route = '/wear_home_confirm';

  @override
  State<WearHomeConfirmScreen> createState() => _WearHomeConfirmScreenState();
}

class _WearHomeConfirmScreenState extends State<WearHomeConfirmScreen>
    with ScreenLifecycleLogging<WearHomeConfirmScreen> {
  final WearFlowController _flow = WearDependencies.I.wearFlowController;
  StreamSubscription<WearFlowState>? _flowSub;
  int _focusedIndex = 0;

  @override
  void initState() {
    super.initState();
    _focusedIndex = _flow.state.homeConfirmFocusedIndex;
    _flow.enterScreen(WearScreenId.homeConfirm);
    _flow.registerScreenActions(
      WearScreenId.homeConfirm,
      WearScreenActionHandler(
        onUp: _focusHome,
        onDown: _focusCancel,
        onSelect: _selectFocused,
        onYes: _goHome,
        onNo: _cancel,
        onBack: _cancel,
        onHome: _goHome,
        onCancel: _cancel,
      ),
    );
    _flowSub = _flow.stateStream.listen(_onFlowState);
  }

  @override
  void dispose() {
    _flowSub?.cancel();
    _flow.unregisterScreenActions(WearScreenId.homeConfirm);
    super.dispose();
  }

  void _onFlowState(WearFlowState state) {
    if (state.screen != WearScreenId.homeConfirm) return;
    final int next = state.homeConfirmFocusedIndex.clamp(0, 1);
    if (next == _focusedIndex) return;
    if (mounted) {
      setState(() => _focusedIndex = next);
    } else {
      _focusedIndex = next;
    }
  }

  void _focusHome() {
    _setFocus(0);
  }

  void _focusCancel() {
    _setFocus(1);
  }

  void _setFocus(int index) {
    if (_focusedIndex != index) {
      setState(() => _focusedIndex = index);
    }
    _flow.setHomeConfirmFocusedIndex(index);
  }

  void _selectFocused() {
    if (_focusedIndex == 0) {
      _goHome();
      return;
    }
    _cancel();
  }

  void _goHome() {
    context.go(WearMenuScreen.route);
  }

  void _cancel() {
    if (context.canPop()) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return WearScreenScaffold(
      showHomeButton: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Вернуться домой',
                style: WearTypography.lable15,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Домой - переход на первый экран после авторизации',
                style: WearTypography.bodyxsm,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              WearPill(
                title: 'Домой',
                subtitle: _focusedIndex == 0 ? 'Выбрано' : null,
                onTap: _goHome,
              ),
              const SizedBox(height: 8),
              WearPill(
                title: 'Отмена',
                subtitle: _focusedIndex == 1 ? 'Выбрано' : null,
                onTap: _cancel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
