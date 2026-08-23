import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/application/wear_availability_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_flow_state.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/presentation/input/wear_print_code_input_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/input/wear_ui_effect_consumer.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_loading.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearAvailabilityCheckScreen extends StatefulWidget {
  const WearAvailabilityCheckScreen({
    super.key,
    required this.product,
    this.initialFlow,
  });
  static const String route = '/wear_availability_check';
  final WearAvailabilityProduct? product;
  final WearAvailabilityFlowState? initialFlow;

  @override
  State<WearAvailabilityCheckScreen> createState() => _State();
}

class _State extends State<WearAvailabilityCheckScreen> {
  late final WearFlowController _flow = WearDependencies.I.wearFlowController;
  late final StreamSubscription<WearAvailabilityRuntimeState> _subscription;
  late WearAvailabilityRuntimeState _state;
  late final WearScreenActionRegistration _actions;
  late final WearUiEffectConsumer _manualInputConsumer;

  @override
  void initState() {
    super.initState();
    _state = _flow.availabilityState;
    _manualInputConsumer = WearUiEffectConsumer(
      authority: _flow.authority,
      kind: WearUiEffectKind.manualBarcodeInput,
      expectedScreen: WearScreenId.availabilityCheck,
      execute: _executeManualInput,
    );
    _subscription = _flow.availabilityStateStream.listen((next) {
      if (mounted) setState(() => _state = next);
    });
    _flow.enterScreen(
      WearScreenId.availabilityCheck,
      extra: widget.initialFlow ?? widget.product,
    );
    _actions = _flow.registerScreenActions(
      WearScreenId.availabilityCheck,
      WearScreenActionHandler(onManualInput: _manualInput),
    );
  }

  @override
  void dispose() {
    _flow.unregisterScreenActions(_actions);
    _manualInputConsumer.dispose();
    unawaited(_subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final WearAvailabilityFlowState flow = _state.flow;
    final WearAvailabilityProduct? product =
        flow.selectedProduct ?? widget.product;
    return WearScreenScaffold(
      showHomeButton: true,
      child: Stack(children: <Widget>[
        Center(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Text(_title(flow.step), style: WearTypography.lable18),
              const SizedBox(height: 8),
              Text(product?.name ?? 'Товар не выбран',
                  textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Text(flow.message ?? _message(flow.step),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              _actionsFor(flow.step),
            ]),
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

  Widget _actionsFor(WearAvailabilityFlowStep step) => switch (step) {
        WearAvailabilityFlowStep.productQuestion => Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                  width: 96,
                  child: WearPill(
                      title: 'Да',
                      onTap: () => _flow.answerAvailability(true))),
              const SizedBox(width: 8),
              SizedBox(
                  width: 96,
                  child: WearPill(
                      title: 'Нет',
                      onTap: () => _flow.answerAvailability(false))),
            ],
          ),
        WearAvailabilityFlowStep.productScan ||
        WearAvailabilityFlowStep.priceTagScan =>
          SizedBox(
            width: 150,
            child: WearPill(
                title: 'Ручной ввод',
                icon: WearImages.barcode,
                onTap: _manualInput),
          ),
        WearAvailabilityFlowStep.priceTagOutdated => SizedBox(
            width: 150,
            child: WearPill(
                title: 'Напечатать',
                icon: WearImages.printer,
                onTap: _flow.printAvailabilityPriceTag),
          ),
        WearAvailabilityFlowStep.photoCapture => SizedBox(
            width: 150,
            child: WearPill(
                title: 'Сделать фото', onTap: _flow.captureAvailabilityPhoto),
          ),
        WearAvailabilityFlowStep.readyToComplete ||
        WearAvailabilityFlowStep.manualInventoryRequired =>
          SizedBox(
            width: 150,
            child: WearPill(
                title: 'Завершить',
                icon: WearImages.ok,
                onTap: _flow.completeAvailability),
          ),
        _ => const SizedBox.shrink(),
      };

  Future<void> _manualInput() async {
    await _manualInputConsumer.request();
  }

  Future<void> _executeManualInput(WearUiEffect effect) async {
    final WearRuntimeAuthority authority = _flow.authority;
    if (!mounted) return;
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
      expectedScreen: WearScreenId.availabilityCheck,
      value: value,
    );
  }

  String _title(WearAvailabilityFlowStep step) => switch (step) {
        WearAvailabilityFlowStep.productQuestion => 'Товар есть на полке?',
        WearAvailabilityFlowStep.productScan => 'Сканирование товара',
        WearAvailabilityFlowStep.priceTagScan => 'Проверка ценника',
        WearAvailabilityFlowStep.priceTagOutdated => 'Ценник неактуален',
        WearAvailabilityFlowStep.photoCapture => 'Фотоконтроль',
        WearAvailabilityFlowStep.readyToComplete => 'Завершение проверки',
        WearAvailabilityFlowStep.manualInventoryRequired =>
          'Требуется действие',
        _ => 'Доступность',
      };

  String _message(WearAvailabilityFlowStep step) => switch (step) {
        WearAvailabilityFlowStep.productScan => 'Отсканируйте ШК товара',
        WearAvailabilityFlowStep.priceTagScan => 'Отсканируйте ценник',
        WearAvailabilityFlowStep.priceTagOutdated => 'Напечатайте новый ценник',
        WearAvailabilityFlowStep.photoCapture => 'Сделайте фотографию товара',
        WearAvailabilityFlowStep.readyToComplete => 'Можно завершить проверку',
        _ => '',
      };
}
