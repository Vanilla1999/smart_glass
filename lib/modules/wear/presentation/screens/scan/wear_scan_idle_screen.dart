import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/infrastructure/screen_lifecycle_logging.dart';
import 'package:smart_glasses/modules/wear/presentation/input/wear_print_code_input_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_svg_icon.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_phone_feature_projection.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearScanIdleScreen extends StatefulWidget {
  const WearScanIdleScreen({super.key});

  static const String route = '/wear_scan_idle';

  @override
  State<WearScanIdleScreen> createState() => _WearScanIdleScreenState();
}

class _WearScanIdleScreenState extends State<WearScanIdleScreen>
    with ScreenLifecycleLogging<WearScanIdleScreen> {
  final WearRuntimeAuthority _authority = WearDependencies.I.authority;
  StreamSubscription<WearRuntimeState>? _runtimeSub;
  late WearScanPhoneProjection _projection;
  int? _executingEffectId;
  bool _effectCallbackScheduled = false;

  @override
  void initState() {
    super.initState();
    _projection = WearScanPhoneProjection.fromState(_authority.state);
    _runtimeSub = _authority.states.listen(_onRuntimeState);
    _schedulePendingManualInput(_authority.state);
  }

  @override
  void dispose() {
    unawaited(_runtimeSub?.cancel());
    super.dispose();
  }

  void _onRuntimeState(WearRuntimeState state) {
    final WearScanPhoneProjection next =
        WearScanPhoneProjection.fromState(state);
    if (mounted) {
      setState(() => _projection = next);
    } else {
      _projection = next;
    }
    _schedulePendingManualInput(state);
  }

  Future<void> _requestManualInput() async {
    final WearRuntimeState snapshot = _authority.state;
    final WearAggregatePayload aggregate =
        snapshot.payloadAs<WearAggregatePayload>();
    if (aggregate.navigation.logicalScreen != WearScreenId.scanIdle) return;
    await _authority.dispatchSemanticInput(
      kind: WearSemanticInputKind.requestUiEffect,
      modality: WearInputModality.touch,
      expectedScreen: WearScreenId.scanIdle,
      expectedSessionEpoch: snapshot.sessionEpoch,
      uiEffectKind: WearUiEffectKind.manualBarcodeInput,
    );
    _schedulePendingManualInput(_authority.state);
  }

  void _schedulePendingManualInput(WearRuntimeState state) {
    if (_effectCallbackScheduled || _executingEffectId != null) return;
    final WearAggregatePayload aggregate =
        state.payloadAs<WearAggregatePayload>();
    if (aggregate.navigation.logicalScreen != WearScreenId.scanIdle ||
        !aggregate.lifecycle.phoneUiActive) {
      return;
    }
    final WearUiEffect? effect =
        aggregate.uiEffects.effectOfKind(WearUiEffectKind.manualBarcodeInput);
    if (effect == null ||
        effect.status != WearUiEffectStatus.pending ||
        effect.sessionEpoch != state.sessionEpoch ||
        effect.expectedScreen != WearScreenId.scanIdle) {
      return;
    }
    _effectCallbackScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _effectCallbackScheduled = false;
      if (!mounted) return;
      unawaited(_consumeManualInput(effect));
    });
  }

  Future<void> _consumeManualInput(WearUiEffect effect) async {
    if (_executingEffectId != null || !mounted) return;
    final bool isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? false;
    if (!isCurrentRoute) return;

    final WearRuntimeState beforeClaim = _authority.state;
    final WearAggregatePayload aggregate =
        beforeClaim.payloadAs<WearAggregatePayload>();
    final WearUiEffect? current = aggregate.uiEffects.effectById(effect.effectId);
    if (current == null ||
        current.status != WearUiEffectStatus.pending ||
        current.sessionEpoch != beforeClaim.sessionEpoch ||
        current.expectedScreen != WearScreenId.scanIdle ||
        aggregate.navigation.logicalScreen != WearScreenId.scanIdle) {
      return;
    }

    final WearDispatchResult claim = await _authority.claimUiEffect(current);
    if (!claim.accepted ||
        claim.sessionEpoch != current.sessionEpoch ||
        !mounted) {
      return;
    }
    _executingEffectId = current.effectId;
    try {
      final String? code = await context.push<String>(
        WearPrintCodeInputScreen.route,
      );
      final String normalized = code?.trim() ?? '';
      final WearDispatchResult result = normalized.isEmpty
          ? await _authority.cancelUiEffect(current)
          : await _authority.completeUiEffect(current, value: normalized);
      if (!result.accepted) {
        await _authority.cancelUiEffect(current);
      }
    } catch (error, stackTrace) {
      print('[WearScanIdleScreen] manual input failed: $error\n$stackTrace');
      await _authority.cancelUiEffect(current);
    } finally {
      if (_executingEffectId == current.effectId) {
        _executingEffectId = null;
      }
      _schedulePendingManualInput(_authority.state);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WearScreenScaffold(
      showHomeButton: true,
      child: Stack(
        children: <Widget>[
          Center(
            child: Padding(
              padding: const EdgeInsets.all(4.5),
              child: _ScanWaitingContent(
                onManualInput: _requestManualInput,
              ),
            ),
          ),
          if (_projection.isLoading)
            Positioned.fill(
              child: _ScanLoadingView(
                statusText: _projection.loadingText,
                icon: _projection.loadingIcon,
              ),
            ),
        ],
      ),
    );
  }
}

class _ScanWaitingContent extends StatelessWidget {
  const _ScanWaitingContent({required this.onManualInput});

  final VoidCallback onManualInput;

  @override
  Widget build(BuildContext context) {
    return Column(
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
          'Наведите камеру\nна штрих-код',
          style: WearTypography.lable.copyWith(
            color: WearColors.textSecondary,
            height: 1.2,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),
        const _ScanStatusLine(text: 'Поиск ШК...'),
        const SizedBox(height: 16),
        _PillButton(
          title: 'Ручной ввод',
          icon: WearImages.barcode,
          onTap: onManualInput,
        ),
      ],
    );
  }
}

class _ScanLoadingView extends StatelessWidget {
  const _ScanLoadingView({
    required this.statusText,
    required this.icon,
  });

  final String statusText;
  final String icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xCCFFFFFF)),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(4.5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _ScanIconBubble(icon: icon),
              const SizedBox(height: 12),
              Text(
                'Сканирование товара',
                style: WearTypography.lable18,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Наведите камеру\nна штрих-код',
                style: WearTypography.lable.copyWith(
                  color: WearColors.textSecondary,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              _ScanStatusLine(text: statusText, icon: icon),
              const SizedBox(height: 10),
              const SizedBox(
                width: 112,
                child: ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    backgroundColor: Color(0x1A464646),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      WearColors.textDefault,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanIconBubble extends StatelessWidget {
  const _ScanIconBubble({this.icon = WearImages.barcode});

  final String icon;

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
          icon,
          size: 22,
          color: WearColors.textDefault,
        ),
      ),
    );
  }
}

class _ScanStatusLine extends StatelessWidget {
  const _ScanStatusLine({
    required this.text,
    this.icon = WearImages.scanerIndicator,
  });

  final String text;
  final String icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        WearSvgIcon(
          icon == WearImages.printer
              ? WearImages.printer
              : WearImages.scanerIndicator,
          size: 16,
          color: WearColors.green,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: WearTypography.lable.copyWith(height: 1.1),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.title,
    required this.onTap,
    this.icon,
  });

  final String title;
  final VoidCallback onTap;
  final String? icon;

  static const double _radius = 33.0;
  static const double _height = 34.0;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WearColors.buttonSecondaryDefault,
      borderRadius: BorderRadius.circular(_radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 138,
          height: _height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    WearSvgIcon(
                      icon!,
                      size: 14,
                      color: WearColors.textDefault,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      title,
                      style: WearTypography.lable.copyWith(fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
