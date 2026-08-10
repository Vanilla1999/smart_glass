import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/data/bdto/data_source/bdto_datasource.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/enum/printer_kind.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/printer_list_item.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/available_printer.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/use_case/get_available_printers_use_case.dart';

void main() {
  test('shares an in-flight printer request', () async {
    final _FakeBdtoDataSource dataSource = _FakeBdtoDataSource();
    final GetAvailablePrintersUseCase useCase =
        GetAvailablePrintersUseCase(dataSource);

    final Future<List<AvailablePrinter>> first = useCase.call();
    final Future<List<AvailablePrinter>> second = useCase.call();

    expect(identical(first, second), isTrue);
    expect(dataSource.callCount, 1);

    dataSource.complete(const <PrinterListItem>[]);
    await expectLater(first, completion(isEmpty));
    await expectLater(second, completion(isEmpty));

    useCase.call();
    expect(dataSource.callCount, 2);
  });
}

class _FakeBdtoDataSource extends BdtoDataSource {
  int callCount = 0;
  Completer<List<PrinterListItem>> _completer =
      Completer<List<PrinterListItem>>();

  @override
  Future<List<PrinterListItem>> getPrinterList({PrinterKind? kind}) {
    callCount += 1;
    return _completer.future;
  }

  void complete(List<PrinterListItem> printers) {
    _completer.complete(printers);
    _completer = Completer<List<PrinterListItem>>();
  }
}
