import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_availability_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/presentation/input/wear_print_code_input_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_loading.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearAvailabilityFillScreen extends StatefulWidget {
  const WearAvailabilityFillScreen({super.key});

  static const String route = '/wear_availability_fill';

  @override
  State<WearAvailabilityFillScreen> createState() =>
      _WearAvailabilityFillScreenState();
}

class _WearAvailabilityFillScreenState
    extends State<WearAvailabilityFillScreen> {
  late final WearScreenActionRegistration _screenActionsRegistration;
  late final StreamSubscription<WearAvailabilityRuntimeState> _subscription;
  late WearAvailabilityRuntimeState _state;

  @override
  void initState() {
    super.initState();
    _state = WearDependencies.I.wearFlowController.availabilityState;
    _subscription = WearDependencies
        .I.wearFlowController.availabilityStateStream
        .listen((next) {
      if (mounted) setState(() => _state = next);
    });
    WearDependencies.I.wearFlowController.enterScreen(
      WearScreenId.availabilityFill,
    );
    _screenActionsRegistration =
        WearDependencies.I.wearFlowController.registerScreenActions(
      WearScreenId.availabilityFill,
      WearScreenActionHandler(
        onSelect: _manualInput,
        onManualInput: _manualInput,
      ),
    );
  }

  @override
  void dispose() {
    WearDependencies.I.wearFlowController
        .unregisterScreenActions(_screenActionsRegistration);
    unawaited(_subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WearScreenScaffold(
      showHomeButton: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 28, 14, 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'Наполнение базы',
              style: WearTypography.lable18,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            if (_state.busy) const WearLoading(size: 44),
            if (_state.busy) const SizedBox(height: 12),
            Text(
              _state.message ?? 'Сканируйте товары с полки',
              style: WearTypography.bodysml,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Добавлено: ${_state.savedCount}',
              style: WearTypography.bodyxsm,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: 150,
                  child: WearPill(
                    title: 'Ручной ввод',
                    icon: WearImages.barcode,
                    onTap: _manualInput,
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: WearPill(
                    title: 'Очистить',
                    icon: WearImages.clear,
                    onTap: WearDependencies
                        .I.wearFlowController.resetAvailabilityFill,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _manualInput() async {
    final WearRuntimeAuthority authority =
        WearDependencies.I.wearFlowController.authority;
    final WearDispatchResult requested = await authority.dispatchSemanticInput(
      kind: WearSemanticInputKind.requestUiEffect,
      modality: WearInputModality.manual,
      expectedScreen: WearScreenId.availabilityFill,
      uiEffectKind: WearUiEffectKind.manualBarcodeInput,
    );
    if (!requested.accepted || !mounted) return;
    final WearUiEffect effect = authority.payload.uiEffects.effects.singleWhere(
      (WearUiEffect value) =>
          value.kind == WearUiEffectKind.manualBarcodeInput,
    );
    final WearDispatchResult claimed = await authority.claimUiEffect(effect);
    if (!claimed.accepted || !mounted) return;
    final String? code = await context.push<String>(
      WearPrintCodeInputScreen.route,
    );
    final String value = code?.trim() ?? '';
    if (value.isEmpty) {
      await authority.cancelUiEffect(effect);
      return;
    }
    await authority.completeUiEffect(effect, value: value);
    await authority.dispatchSemanticInput(
      kind: WearSemanticInputKind.barcode,
      modality: WearInputModality.manual,
      expectedScreen: WearScreenId.availabilityFill,
      value: value,
    );
  }
}
