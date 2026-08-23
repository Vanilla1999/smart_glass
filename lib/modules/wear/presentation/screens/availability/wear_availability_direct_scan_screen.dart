import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/application/wear_availability_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/presentation/input/wear_print_code_input_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_loading.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_scaling_list_view.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearAvailabilityDirectScanScreen extends StatefulWidget {
  const WearAvailabilityDirectScanScreen({super.key});
  static const String route = '/wear_availability_direct_scan';

  @override
  State<WearAvailabilityDirectScanScreen> createState() => _State();
}

class _State extends State<WearAvailabilityDirectScanScreen> {
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
    final List<WearAvailabilityProduct> duplicates = _state.duplicateProducts;
    return WearScreenScaffold(
      showHomeButton: true,
      scrollController: _scroll,
      child: Stack(children: <Widget>[
        Center(
          child: duplicates.isEmpty
              ? Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  Text('Сканирование товара', style: WearTypography.lable18),
                  const SizedBox(height: 12),
                  Text(
                    _state.message ?? 'Наведите камеру на штрих-код',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 150,
                    child: WearPill(
                      title: 'Ручной ввод',
                      icon: WearImages.barcode,
                      onTap: _manualInput,
                    ),
                  ),
                ])
              : WearScalingListView(
                  controller: _scroll,
                  itemCount: duplicates.length + 2,
                  itemExtent: 56,
                  padding: const EdgeInsets.fromLTRB(0, 40, 0, 4.5),
                  itemBuilder: (_, int index) {
                    if (index == 0) {
                      return Align(
                        alignment: Alignment.topCenter,
                        child: Text('Дубль ШК', style: WearTypography.lable),
                      );
                    }
                    if (index == duplicates.length + 1) {
                      return const SizedBox.shrink();
                    }
                    final WearAvailabilityProduct product =
                        duplicates[index - 1];
                    return WearPill(
                      title: product.name,
                      subtitle: 'Код ${product.code}',
                      icon: WearImages.barcode,
                      onTap: () => _flow.selectAvailabilityItem(product),
                    );
                  },
                  onFocusChanged: (int index) => _flow.focusAvailabilityItem(
                    (index - 1).clamp(0, duplicates.length - 1),
                  ),
                ),
        ),
        if (_state.busy)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0xCCFFFFFF),
              child: Center(child: WearLoading(size: 44)),
            ),
          ),
      ]),
    );
  }

  Future<void> _manualInput() async {
    final WearRuntimeAuthority authority = _flow.authority;
    final WearDispatchResult requested = await authority.dispatchSemanticInput(
      kind: WearSemanticInputKind.requestUiEffect,
      modality: WearInputModality.manual,
      expectedScreen: WearScreenId.availabilityDirectScan,
      uiEffectKind: WearUiEffectKind.manualBarcodeInput,
    );
    if (!requested.accepted || !mounted) return;
    final WearUiEffect effect = authority.payload.uiEffects.effects.singleWhere(
      (WearUiEffect value) =>
          value.kind == WearUiEffectKind.manualBarcodeInput,
    );
    final WearDispatchResult claimed = await authority.claimUiEffect(effect);
    if (!claimed.accepted || !mounted) return;
    final String? code = await context.push<String>(WearPrintCodeInputScreen.route);
    final String value = code?.trim() ?? '';
    if (value.isEmpty) {
      await authority.cancelUiEffect(effect);
      return;
    }
    await authority.completeUiEffect(effect, value: value);
    await authority.dispatchSemanticInput(
      kind: WearSemanticInputKind.barcode,
      modality: WearInputModality.manual,
      expectedScreen: WearScreenId.availabilityDirectScan,
      value: value,
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
