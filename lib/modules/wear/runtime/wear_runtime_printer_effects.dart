import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/available_printer.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_effect_router.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

typedef WearPrinterEffectLoader = Future<List<AvailablePrinter>> Function();
typedef WearPrinterEffectNavigation = Future<void> Function(
  WearScreenId screen, {
  Object? extra,
  bool replaceCurrent,
});

class WearPrinterEffectExecutor implements WearEffectExecutor {
  const WearPrinterEffectExecutor({
    required WearPrinterEffectLoader loadPrinters,
    required WearPrinterEffectNavigation navigate,
  })  : _loadPrinters = loadPrinters,
        _navigate = navigate;

  final WearPrinterEffectLoader _loadPrinters;
  final WearPrinterEffectNavigation _navigate;

  @override
  bool handles(WearEffect effect) {
    return effect is WearLoadPrintersEffect ||
        effect is WearNavigateAfterPrinterSelectionEffect;
  }

  @override
  Future<WearIntent?> execute(WearEffect effect) async {
    if (effect is WearLoadPrintersEffect) {
      try {
        final List<AvailablePrinter> available = await _loadPrinters();
        final List<WearPrinter> printers = available
            .map(
              (AvailablePrinter item) => WearPrinter(
                id: item.number,
                name: item.name,
              ),
            )
            .toList(growable: false);
        return WearPrintersLoaded(
          sessionEpoch: effect.sessionEpoch,
          operationId: effect.operationId,
          printers: printers,
        );
      } catch (error) {
        return WearPrintersLoadFailed(
          sessionEpoch: effect.sessionEpoch,
          operationId: effect.operationId,
          message: _messageFor(error),
        );
      }
    }

    if (effect is WearNavigateAfterPrinterSelectionEffect) {
      try {
        await _navigate(
          WearScreenId.scanIdle,
          extra: effect.selection,
        );
        return WearOperationResult(
          sessionEpoch: effect.sessionEpoch,
          operationId: effect.operationId,
          kind: effect.kind,
        );
      } catch (error) {
        return WearPrinterNavigationFailed(
          sessionEpoch: effect.sessionEpoch,
          operationId: effect.operationId,
          message: _messageFor(error),
        );
      }
    }

    throw StateError('Unsupported printer effect ${effect.runtimeType}');
  }

  String _messageFor(Object error) {
    final String message = error.toString();
    return message.startsWith('Exception: ')
        ? message.substring('Exception: '.length)
        : message;
  }
}
