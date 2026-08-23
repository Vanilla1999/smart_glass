import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_svg_icon.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_projection.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';
import 'package:smart_glasses/modules/wear/services/wear_voice_session.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearContinueScanScreen extends StatefulWidget {
  const WearContinueScanScreen({super.key});

  static const String route = '/wear_continue_scan';

  @override
  State<WearContinueScanScreen> createState() => _WearContinueScanScreenState();
}

class _WearContinueScanScreenState extends State<WearContinueScanScreen>
    with WidgetsBindingObserver {
  final _flow = WearDependencies.I.wearFlowController;
  final _authority = WearDependencies.I.authority;
  late final WearScreenActionRegistration _screenActionsRegistration;
  StreamSubscription<WearRuntimeState>? _runtimeSub;
  int _selectedButtonIndex = 0;
  bool _isActionInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedButtonIndex = _projectedFocus(_authority.state);
    _screenActionsRegistration = _flow.registerScreenActions(
      WearScreenId.continueScan,
      WearScreenActionHandler(
        onUp: _onVoiceUp,
        onDown: _onVoiceDown,
        onSelect: _onVoiceSelect,
        onContinue: _continueScanning,
        onFinish: _finishScanning,
      ),
    );
    _runtimeSub = _authority.states.listen(_onRuntimeState);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        WearVoiceSession.I
            .ensureHealthy(reason: 'continue_scan_enter')
            .catchError(
          (Object error, StackTrace stackTrace) {
            print(
                '[ContinueScan] voice health-check failed: $error\n$stackTrace');
          },
        ),
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print(
      '[ContinueScan] lifecycle state=$state '
      'selectedIndex=$_selectedButtonIndex actionInProgress=$_isActionInProgress',
    );
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          WearVoiceSession.I
              .ensureHealthy(reason: 'continue_scan_resumed')
              .catchError((Object error, StackTrace stackTrace) {
            print(
              '[ContinueScan] voice health-check failed: $error\n$stackTrace',
            );
          }),
        );
      });
    }
  }

  @override
  void dispose() {
    _runtimeSub?.cancel();
    _flow.unregisterScreenActions(_screenActionsRegistration);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onRuntimeState(WearRuntimeState state) {
    final WearPhoneProjection projection =
        WearRuntimeProjection.projectPhone(state);
    if (projection.logicalScreen != WearScreenId.continueScan) return;
    final int next = projection.focusedIndex.clamp(0, 1);
    if (next == _selectedButtonIndex) return;
    if (mounted) {
      setState(() => _selectedButtonIndex = next);
    } else {
      _selectedButtonIndex = next;
    }
  }

  int _projectedFocus(WearRuntimeState state) {
    final WearPhoneProjection projection =
        WearRuntimeProjection.projectPhone(state);
    if (projection.logicalScreen != WearScreenId.continueScan) return 0;
    return projection.focusedIndex.clamp(0, 1);
  }

  void _onVoiceUp() {
    print(
      '[ContinueScan] _onVoiceUp called, '
      '_selectedButtonIndex=$_selectedButtonIndex',
    );
    _setFocusedButton(0);
  }

  void _onVoiceDown() {
    print(
      '[ContinueScan] _onVoiceDown called, '
      '_selectedButtonIndex=$_selectedButtonIndex',
    );
    _setFocusedButton(1);
  }

  void _onVoiceSelect() {
    print(
      '[ContinueScan] _onVoiceSelect called, '
      '_selectedButtonIndex=$_selectedButtonIndex, '
      '_isActionInProgress=$_isActionInProgress',
    );
    if (_isActionInProgress) return;
    if (_selectedButtonIndex == 0) {
      unawaited(_continueScanning());
    } else {
      unawaited(_finishScanning());
    }
  }

  Future<void> _continueScanning() async {
    if (_isActionInProgress) return;
    _isActionInProgress = true;
    final bool accepted = await _flow.commitPresentationFocus(
      WearScreenId.continueScan,
      0,
    );
    if (!accepted) {
      _isActionInProgress = false;
      return;
    }
    await _flow.requestNavigation(
      WearScreenId.scanIdle,
      extra: _authority.features.printer.selection,
      replaceCurrent: true,
    );
  }

  Future<void> _finishScanning() async {
    if (_isActionInProgress) return;
    _isActionInProgress = true;
    final bool accepted = await _flow.commitPresentationFocus(
      WearScreenId.continueScan,
      1,
    );
    if (!accepted) {
      _isActionInProgress = false;
      return;
    }
    await _flow.requestNavigation(
      WearScreenId.menu,
      replaceCurrent: true,
    );
  }

  void _setFocusedButton(int index) {
    print(
      '[ContinueScan] _setFocusedButton index=$index, '
      'current=$_selectedButtonIndex',
    );
    if (_selectedButtonIndex == index) return;
    _flow.setContinueScanFocusedIndex(index);
  }

  @override
  Widget build(BuildContext context) {
    return WearScreenScaffold(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(4.5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const _ScanIconBubble(),
              const SizedBox(height: 12),
              Text(
                'Сканирование товара',
                style: WearTypography.lable18,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Готовы продолжить?',
                style: WearTypography.lable.copyWith(
                  color: WearColors.textSecondary,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    width: 132,
                    child: WearPill(
                      title: 'Продолжить',
                      onTap: _continueScanning,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 132,
                    child: WearPill(
                      title: 'Завершить',
                      onTap: _finishScanning,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanIconBubble extends StatelessWidget {
  const _ScanIconBubble();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        color: WearColors.buttonSecondaryDefault,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: WearSvgIcon(
          WearImages.barcode,
          size: 22,
          color: WearColors.textDefault,
        ),
      ),
    );
  }
}
