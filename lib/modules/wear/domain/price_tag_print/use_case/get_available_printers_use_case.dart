import 'package:smart_glasses/modules/wear/data/bdto/data_source/bdto_datasource.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/enum/printer_kind.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/printer_list_item.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/available_printer.dart';

class GetAvailablePrintersUseCase {
  GetAvailablePrintersUseCase(this._bdtoDataSource);

  final BdtoDataSource _bdtoDataSource;
  Future<List<AvailablePrinter>>? _inFlight;

  /// Возвращает список доступных принтеров для моментальной печати.
  Future<List<AvailablePrinter>> call() {
    final Future<List<AvailablePrinter>>? existing = _inFlight;
    if (existing != null) return existing;

    late final Future<List<AvailablePrinter>> operation;
    operation = _load().whenComplete(() {
      if (identical(_inFlight, operation)) _inFlight = null;
    });
    _inFlight = operation;
    return operation;
  }

  Future<List<AvailablePrinter>> _load() async {
    final List<PrinterListItem> result =
        await _bdtoDataSource.getPrinterList(kind: PrinterKind.mobile);
    return result
        .map((PrinterListItem item) => AvailablePrinter(
              name: item.name,
              number: item.alias,
            ))
        .toList();
  }
}
