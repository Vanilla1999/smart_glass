import 'package:smart_glasses/modules/wear/data/bdto/data_source/bdto_datasource.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/enum/price_tag_color.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/enum/print_mode.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/enum/printer_mobility_type.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/print_add_art_result.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/print_task_get_result.dart';

class PrintPriceTagUseCase {
  PrintPriceTagUseCase(this._bdtoDataSource);

  final BdtoDataSource _bdtoDataSource;

  /// Создает новое задание печати, добавляет ценник и печатает его
  /// на нужном принтере (обычный/акционный).
  ///
  /// Возвращает название принтера, на который был отправлен запрос на печать
  /// при успешной печати.
  ///
  /// При провале выбрасывает исключение с текстом ошибки.
  ///
  /// - [userId] — ID пользователя.
  /// - [employeeId] — ID сотрудника.
  /// - [articleId] — ID товара.
  /// - [whiteTagsPrinterName] — имя принтера для обычных ценников (белые).
  /// - [yellowTagsPrinterName] — имя принтера для акционных ценников (желтые).
  Future<String> call({
    required int userId,
    required int employeeId,
    required int articleId,
    required String whiteTagsPrinterName,
    required String yellowTagsPrinterName,
  }) async {
    // 1. Создаем новое задание печати или получаем уже существующее.
    // За очередь при этом не нужно беспокоиться - по факту из задания будет
    // только браться информация о пользователя, для самой печати автоматически
    // создается новая очередь на один ценник.
    final PrintGetTaskResult taskResult =
        await _bdtoDataSource.getOrCreatePrintTask(
      userId: userId,
      employeeId: employeeId,
      forceNew: false,
      mobility: PrinterMobilityType.mobile,
    );
    // 2. Получаем цвет ценника по ID товара.
    final priceTagInfo = await _bdtoDataSource.getPriceTagInfo(
      artId: articleId,
    );
    // 3. Выбираем нужный принтер в зависимости от цвета ценника.
    final String printerName = priceTagInfo.color == PriceTagColor.yellow
        ? yellowTagsPrinterName
        : whiteTagsPrinterName;
    // 4. Отправляем на моментальную печать.
    final PrintAddArtResult addResult =
        await _bdtoDataSource.addPriceTagToPrintQueue(
      taskId: taskResult.taskId,
      articleId: articleId,
      mobility: PrinterMobilityType.mobile,
      printerName: printerName,
      printMode: PrintMode.instant,
    );
    if (addResult.resultCode != 0) {
      throw Exception(
          'Не удалось отправить на печать, причина: ${addResult.message}');
    }
    return printerName;
  }
}
