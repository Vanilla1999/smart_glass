import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_mock_config.dart';
import 'package:smart_glasses/modules/wear/application/wear_status_state.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_effect_router.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_scan_sequencing_reducer.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_scan_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

typedef WearScanEffectLookup = Future<List<BarcodeProductInfo>> Function(
  String barcode,
);
typedef WearScanEffectPrint = Future<String> Function(
  BarcodeProductInfo product,
  WearPrinterSelection selection,
);
typedef WearScanEffectNavigation = Future<void> Function(
  WearScreenId screen, {
  Object? extra,
  bool replaceCurrent,
});
typedef WearScanEffectStatus = Future<void> Function(
  WearStatusScreenArgs args, {
  required WearStatusCompletion completion,
});
typedef WearScanEffectDelay = Future<void> Function(Duration duration);

class WearScanEffectExecutor
    implements WearEffectExecutor, WearEffectExecutorLease {
  WearScanEffectExecutor({
    required WearScanEffectLookup lookup,
    required WearScanEffectPrint print,
    required WearScanEffectNavigation navigate,
    required WearScanEffectStatus presentStatus,
    WearScanEffectDelay delay = _defaultDelay,
  })  : _lookup = lookup,
        _print = print,
        _navigate = navigate,
        _presentStatus = presentStatus,
        _delay = delay;

  final WearScanEffectLookup _lookup;
  final WearScanEffectPrint _print;
  final WearScanEffectNavigation _navigate;
  final WearScanEffectStatus _presentStatus;
  final WearScanEffectDelay _delay;
  bool _active = true;

  static Future<void> _defaultDelay(Duration duration) {
    return Future<void>.delayed(duration);
  }

  @override
  String get registrationKey => 'scan';

  @override
  bool get isActive => _active;

  @override
  void deactivate() {
    _active = false;
  }

  @override
  bool handles(WearEffect effect) {
    return effect is WearLookupBarcodeEffect ||
        effect is WearPrintPriceTagEffect ||
        effect is WearNavigateScanEffect ||
        effect is WearPresentScanStatusEffect ||
        effect is WearScanStatusDelayEffect;
  }

  @override
  Future<WearIntent?> execute(WearEffect effect) async {
    if (!_active) throw StateError('Scan effect executor is inactive');

    if (effect is WearLookupBarcodeEffect) {
      try {
        final List<BarcodeProductInfo> products = WearMockConfig.isEnabled
            ? _mockProducts(effect.barcode)
            : await _lookup(effect.barcode);
        return WearBarcodeLookupSucceeded(
          sessionEpoch: effect.sessionEpoch,
          operationId: effect.operationId,
          products: List<BarcodeProductInfo>.unmodifiable(products),
        );
      } catch (error) {
        return WearBarcodeLookupFailed(
          sessionEpoch: effect.sessionEpoch,
          operationId: effect.operationId,
          message: _messageFor(error),
        );
      }
    }

    if (effect is WearPrintPriceTagEffect) {
      try {
        final String printerName = WearMockConfig.isEnabled
            ? (effect.product.id.isEven
                ? effect.selection.yellowPrinter.name
                : effect.selection.whitePrinter.name)
            : await _print(effect.product, effect.selection);
        return WearPriceTagPrintSucceeded(
          sessionEpoch: effect.sessionEpoch,
          operationId: effect.operationId,
          printerName: printerName,
        );
      } catch (error) {
        return WearPriceTagPrintFailed(
          sessionEpoch: effect.sessionEpoch,
          operationId: effect.operationId,
          message: _messageFor(error),
        );
      }
    }

    if (effect is WearNavigateScanEffect) {
      try {
        await _navigate(
          effect.screen,
          extra: effect.extra,
          replaceCurrent: effect.replaceCurrent,
        );
        return WearOperationResult(
          sessionEpoch: effect.sessionEpoch,
          operationId: effect.operationId,
          kind: effect.kind,
        );
      } catch (error) {
        return WearScanNavigationFailed(
          sessionEpoch: effect.sessionEpoch,
          operationId: effect.operationId,
          message: _messageFor(error),
        );
      }
    }

    if (effect is WearPresentScanStatusEffect) {
      try {
        await _presentStatus(
          effect.args,
          completion: const WearStatusCompletion.stay(),
        );
        return WearScanStatusPresented(
          sessionEpoch: effect.sessionEpoch,
          operationId: effect.operationId,
        );
      } catch (error) {
        return WearScanStatusPresentationFailed(
          sessionEpoch: effect.sessionEpoch,
          operationId: effect.operationId,
          message: _messageFor(error),
        );
      }
    }

    if (effect is WearScanStatusDelayEffect) {
      try {
        await _delay(effect.duration);
        return WearScanStatusElapsed(
          sessionEpoch: effect.sessionEpoch,
          operationId: effect.operationId,
          target: effect.target,
        );
      } catch (error) {
        return WearScanStatusDelayFailed(
          sessionEpoch: effect.sessionEpoch,
          operationId: effect.operationId,
          message: _messageFor(error),
        );
      }
    }

    throw StateError('Unsupported scan effect ${effect.runtimeType}');
  }

  static List<BarcodeProductInfo> _mockProducts(String barcode) {
    if (barcode.endsWith('2')) {
      return <BarcodeProductInfo>[
        BarcodeProductInfo(
          id: 1002001,
          name: 'MOCK Молоко 2,5% 930 мл',
          articleRest: 24,
        ),
        BarcodeProductInfo(
          id: 1002002,
          name: 'MOCK Молоко 3,2% 930 мл',
          articleRest: 16,
        ),
      ];
    }
    return <BarcodeProductInfo>[
      BarcodeProductInfo(
        id: 1001001,
        name: 'MOCK Товар $barcode',
        articleRest: 42,
      ),
    ];
  }

  String _messageFor(Object error) {
    final String message = error.toString();
    return message.startsWith('Exception: ')
        ? message.substring('Exception: '.length)
        : message;
  }
}
