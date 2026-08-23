import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/infrastructure/screen_lifecycle_logging.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/menu/wear_menu_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_projection.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearHomeConfirmScreen extends StatefulWidget {
  const WearHomeConfirmScreen({super.key});

  static const String route = '/wear_home_confirm';

  @override
  State<WearHomeConfirmScreen> createState() => _WearHomeConfirmScreenState();
}

class _WearHomeConfirmScreenState extends State<WearHomeConfirmScreen>
    with ScreenLifecycleLogging<WearHomeConfirmScreen> {
  final _flow = WearDependencies.I.wearFlowController;
  final _authority = WearDependencies.I.authority;
  late final WearScreenActionRegistration _screenActionsRegistration;
  StreamSubscription<WearRuntimeState>? _runtimeSub;
  int _focusedIndex = 0;

  @override
  void initState() {
    super.initState();
    _focusedIndex = _projectedFocus(_authority.state);
    _screenActionsRegistration = _flow.registerScreenActions(
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
    _runtimeSub = _authority.states.listen(_onRuntimeState);
  }

  @override
  void dispose() {
    _runtimeSub?.cancel();
    _flow.unregisterScreenActions(_screenActionsRegistration);
    super.dispose();
  }

  void _onRuntimeState(WearRuntimeState state) {
    final WearPhoneProjection projection =
        WearRuntimeProjection.projectPhone(state);
    if (projection.logicalScreen != WearScreenId.homeConfirm) return;
    final int next = projection.focusedIndex.clamp(0, 1);
    if (next == _focusedIndex) return;
    if (mounted) {
      setState(() => _focusedIndex = next);
    } else {
      _focusedIndex = next;
    }
  }

  int _projectedFocus(WearRuntimeState state) {
    final WearPhoneProjection projection =
        WearRuntimeProjection.projectPhone(state);
    if (projection.logicalScreen != WearScreenId.homeConfirm) return 0;
    return projection.focusedIndex.clamp(0, 1);
  }

  void _focusHome() {
    _flow.setHomeConfirmFocusedIndex(0);
  }

  void _focusCancel() {
    _flow.setHomeConfirmFocusedIndex(1);
  }

  Future<void> _selectFocused() async {
    if (_focusedIndex == 0) {
      await _goHome();
      return;
    }
    await _cancel();
  }

  Future<void> _goHome() async {
    final bool accepted = await _flow.commitPresentationFocus(
      WearScreenId.homeConfirm,
      0,
    );
    if (!accepted || !mounted) return;
    context.go(WearMenuScreen.route);
  }

  Future<void> _cancel() async {
    final bool accepted = await _flow.commitPresentationFocus(
      WearScreenId.homeConfirm,
      1,
    );
    if (!accepted || !mounted) return;
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
