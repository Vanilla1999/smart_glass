import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/config/wear_mock_config.dart';
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/available_printer.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/use_case/get_available_printers_use_case.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer_selection.dart';

class WearPrinterStatusService {
  const WearPrinterStatusService({GetAvailablePrintersUseCase? useCase})
      : _useCase = useCase;

  final GetAvailablePrintersUseCase? _useCase;

  Future<bool> isSelectedPrinterAvailable() async {
    final WearPrinterSelection? selection = WearSession.printerSelectionOrNull;
    if (selection == null) return false;

    if (WearMockConfig.isEnabled) return true;

    try {
      final GetAvailablePrintersUseCase useCase =
          _useCase ?? WearDependencies.I.getAvailablePrintersUseCase();
      final List<AvailablePrinter> availablePrinters = await useCase.call();
      final bool whitePrinterAvailable = availablePrinters.any(
        (AvailablePrinter printer) => _matches(
            printer, selection.whitePrinter.id, selection.whitePrinter.name),
      );
      final bool yellowPrinterAvailable = availablePrinters.any(
        (AvailablePrinter printer) => _matches(
            printer, selection.yellowPrinter.id, selection.yellowPrinter.name),
      );
      return whitePrinterAvailable && yellowPrinterAvailable;
    } catch (_) {
      return false;
    }
  }

  bool _matches(AvailablePrinter printer, String id, String name) {
    return printer.number == id || printer.name == name;
  }
}
