import 'package:smart_glasses/modules/wear/data/bdto/data_source/bdto_datasource.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/enum/printer_kind.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/printer_list_item.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/available_printer.dart';

class GetAvailablePrintersUseCase {
  GetAvailablePrintersUseCase(this._bdtoDataSource);

  final BdtoDataSource _bdtoDataSource;

  /// Возвращает список доступных принтеров для моментальной печати.
  Future<List<AvailablePrinter>> call() async {
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
