import 'package:fbdb/fbdb.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/barcode_info.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/enum/barcode_mode.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/enum/price_tag_action_flag.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/enum/price_tag_color.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/enum/print_mode.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/enum/printer_kind.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/enum/printer_mobility_type.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/enum/printer_selection_type.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/enum/printer_subkind.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/price_tag_info.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/price_tag_type.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/print_add_art_result.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/print_price_tags_result.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/print_task_get_result.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/printer_list_item.dart';
import 'package:smart_glasses/modules/wear/data/bdto/model/printer_selection_result.dart';
import 'package:smart_glasses/modules/wear/data/bdto/data_source/fbdb_error_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Позволяет взаимодействовать с БД Firebird торгового объекта.
///
/// Перед работой с методами необходимо вызвать метод [open].
///
/// Сам класс рекомендуется использовать как синглтон, чтобы не открывать
/// каждый раз соединение с БД. Ну и при завершении работы ОБЯЗАТЕЛЬНО
/// вызвать метод [close].
class BdtoDataSource {
  FbDb? _db;
  SharedPreferences? _prefs;
  bool get isOpen => _db != null;

  Future<void> open() async {
    _prefs ??= await SharedPreferences.getInstance();
    if (_db != null) {
      return;
    }
    print('BDTO opening connection...');
    final String host = _getConfig('DBTO_HOST');
    final String portValue = _getConfig('DBTO_PORT');
    final int port = int.tryParse(portValue) ??
        (throw StateError('DBTO_PORT is not a valid int: $portValue'));
    final String database = _getConfig('DBTO_PATH');
    final String user = _getConfig('DBTO_USER');
    final String password = _getConfig('DBTO_PASSWORD');
    final String role = _getConfig('DBTO_ROLE');

    _db = await FbDb.attach(
      host: host,
      port: port,
      database: database,
      user: user,
      password: password,
      role: role,
    );
  }

  Future<void> reconnect() async {
    _db = null;
    await open();
  }

  String _getConfig(String key) {
    final String? value = _prefs?.getString(key);
    if (value != null && value.isNotEmpty) {
      return value;
    }
    return _requireEnv(key);
  }

  /// (`PPRINT_PRINTERSORT`)
  ///
  /// Получить тип выбора принтера для печати.
  Future<PrinterSelectionResult> getPrinterSelectionType() async {
    return _withReconnect(() async {
      final FbDb db = _requireDb();
      final FbQuery q = db.query();
      try {
        await q.openCursor(
          sql: 'select RES_CODE, RES from PPRINT_PRINTERSORT(?, ?)',
          parameters: <Object?>[null, null],
        );
        final Map<String, dynamic>? row = await q.fetchOneAsMap();
        if (row == null) {
          throw Exception('Процедура PPRINT_PRINTERSORT не вернула результат');
        }
        return PrinterSelectionResult(
          selectionType: PrinterSelectionType.fromCode(
            _asInt(row['RES_CODE']),
          ),
          message: _asString(row['RES']) ?? '',
        );
      } finally {
        await q.close();
      }
    });
  }

  /// (`PPRINT_PRINTERLIST`)
  ///
  /// Получить список принтеров.
  ///
  /// - [kind] - фильтр по типу принтера. `null` - любые допустимые принтеры.
  /// - [alias] - алиас принтера, добытый, например, сканированием. Может быть `null`.
  Future<List<PrinterListItem>> getPrinterList({
    PrinterKind? kind,
  }) async {
    return _withReconnect(() async {
      final FbDb db = _requireDb();
      final FbQuery q = db.query();
      try {
        await q.openCursor(
          sql: 'select NAME, ALIAS, KIND, SUBKIND '
              'from PPRINT_PRINTERLIST(?, ?, ?, ?)',
          parameters: <Object?>[kind?.dbValue, null, null, null],
        );
        final List<Map<String, dynamic>> rows = await q.fetchAllAsMaps();
        return rows
            .map(
              (Map<String, dynamic> row) => PrinterListItem(
                name: _asString(row['NAME']) ?? '',
                alias: _asString(row['ALIAS']) ?? '',
                kind: PrinterKind.fromDbValue(_asString(row['KIND'])),
                subkind: PrinterSubkind.fromDbValue(_asString(row['SUBKIND'])),
              ),
            )
            .toList();
      } finally {
        await q.close();
      }
    });
  }

  /// (`PPRINT_INFO_BARCODE2`)
  ///
  /// Возвращает информацию по ШК.
  ///
  /// - [barcode] - сканированная строка штрихкода.
  ///   Важно: для распознавания ШК принтера к нему необходимо вручную
  ///   добавлять слово PRINTER (например, PRINTER28).
  ///
  /// - [isWeightless] - определять весовые ШК без веса.
  ///
  /// - [itemLimit] - ограничение количества позиций при неоднозначном ШК.
  ///   `null` - нет ограничения.
  ///
  /// - [ownerId] - идентификатор приложения для отправки лога в DATALAKE.
  Future<List<BarcodeInfo>> getBarcodeInfo({
    required String barcode,
    required bool isWeightless,
    int? itemLimit,
    int? ownerId,
  }) async {
    return _withReconnect(() async {
      final FbDb db = _requireDb();
      final FbQuery q = db.query();
      final String? flag = isWeightless ? 'G' : null;
      try {
        await q.openCursor(
          sql: 'select MODE, ID, MES, NAME, WEIGHT, ID_PLARTPRICE, '
              'ID_NOTART, ARTREST, ARTRESTLOT '
              'from PPRINT_INFO_BARCODE2(?, ?, ?, ?)',
          parameters: <Object?>[barcode, flag, itemLimit, ownerId],
        );
        final List<Map<String, dynamic>> rows = await q.fetchAllAsMaps();
        return rows
            .map(
              (Map<String, dynamic> row) => BarcodeInfo(
                mode: BarcodeType.fromDbValue(_asString(row['MODE'])),
                entityId: _asInt(row['ID']),
                message: _asString(row['MES']),
                name: _asString(row['NAME']),
                weight: _asDouble(row['WEIGHT']),
                priceListId: _asInt(row['ID_PLARTPRICE']),
                priceTagId: _asInt(row['ID_NOTART']),
                articleRest: _asDouble(row['ARTREST']),
                articleRestLot: _asDouble(row['ARTRESTLOT']),
              ),
            )
            .toList();
      } finally {
        await q.close();
      }
    });
  }

  /// (`PPRINT_SCHEMALIST`)
  ///
  /// Возвращает доступные форматы ценников.
  ///
  /// - [printerType] - тип принтера (A4 или мобильный/термо).
  Future<List<PriceTagType>> getPriceTagsTypes({
    required PrinterKind printerType,
  }) async {
    return _withReconnect(() async {
      final FbDb db = _requireDb();
      final FbQuery q = db.query();
      try {
        // WEBFLAG char(1) — фильтр спецпечати. Всегда передавайте '1'.
        await q.openCursor(
          sql: 'select RID_REPORT, RCAPTION, RSCHEME, RSORTER '
              'from PPRINT_SCHEMALIST(?, ?, ?)',
          parameters: <Object?>[printerType.dbValue, '1', null],
        );
        final List<Map<String, dynamic>> rows = await q.fetchAllAsMaps();
        return rows
            .map(
              (Map<String, dynamic> row) => PriceTagType(
                reportId: _asInt(row['RID_REPORT']) ?? 0,
                caption: _asString(row['RCAPTION']) ?? '',
                scheme: _asString(row['RSCHEME']) ?? '',
                sortOrder: _asInt(row['RSORTER']) ?? 0,
              ),
            )
            .toList();
      } finally {
        await q.close();
      }
    });
  }

  /// (`PPRINT_CENNIK2`)
  ///
  /// Возвращает цвет ценника и краткое наименование товара по ID товара:
  /// `white` — неакционный, `yellow` — акционный.
  Future<PriceTagInfo> getPriceTagInfo({
    required int artId,
  }) async {
    return _withReconnect(() async {
      final FbDb db = _requireDb();
      final FbQuery q = db.query();
      try {
        await q.openCursor(
          sql: 'select R_COLOR, R_ARTNAME '
              'from PPRINT_CENNIK2(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          parameters: <Object?>[
            'U',
            null,
            artId.toString(),
            null,
            null,
            'any',
            '0',
            '0',
            null,
            '0',
            '0',
            null,
            '!',
            null,
            null,
            null,
            null,
            null,
          ],
        );
        final Map<String, dynamic>? row = await q.fetchOneAsMap();
        if (row == null) {
          throw Exception('PPRINT_CENNIK2 не вернула результат');
        }
        return PriceTagInfo(
          color: PriceTagColor.fromDbValue(_asInt(row['R_COLOR'])),
          name: _asString(row['R_ARTNAME']) ?? 'Название не указано',
        );
      } finally {
        await q.close();
      }
    });
  }

  /// (`PPRINT_GETTASK`)
  ///
  /// Получить (или создать) задание печати.
  ///
  /// - [userId] - ID пользователя.
  ///
  /// - [employeeId] - ID сотрудника/пользователя.
  ///
  /// - [forceNew] - флаг принудительного создания нового задания.
  ///
  /// - [mobility] - тип принтера (`O` / `M`).
  Future<PrintGetTaskResult> getOrCreatePrintTask({
    required int userId,
    required int employeeId,
    required bool forceNew,
    required PrinterMobilityType mobility,
  }) async {
    return _withReconnect(() async {
      final FbDb db = _requireDb();
      final FbQuery q = db.query();
      try {
        await q.openCursor(
          sql: 'select ID_SHTASK from PPRINT_GETTASK(?, ?, ?, ?)',
          parameters: <Object?>[
            userId,
            employeeId,
            forceNew ? '1' : '0',
            mobility.dbValue,
          ],
        );
        final Map<String, dynamic>? row = await q.fetchOneAsMap();
        if (row == null) {
          throw Exception('PPRINT_GETTASK не вернула результат');
        }
        return PrintGetTaskResult(
          taskId: _asInt(row['ID_SHTASK']) ?? 0,
        );
      } finally {
        await q.close();
      }
    });
  }

  /// (`PPRINT_PRINTADDART`)
  ///
  /// Добавляет ценник в очередь печати.
  ///
  /// - [taskId] - идентификатор задания печати (если используется существующее).
  ///   Для мгновенной печати можно передавать `null`.
  ///
  /// - [articleId] - ID товара для печати.
  ///
  /// - [mobility] - тип принтера (A4, мобильный или отложенный).
  ///
  /// - [printerName] - имя или алиас принтера.
  ///
  /// - [appMode] - идентификатор приложения.
  ///
  /// - [printMode] - режим печати.
  Future<PrintAddArtResult> addPriceTagToPrintQueue({
    int? taskId,
    required int articleId,
    required PrinterMobilityType mobility,
    required String printerName,
    required PrintMode printMode,
  }) async {
    return _withReconnect(() async {
      final FbDb db = _requireDb();
      final FbQuery q = db.query();
      try {
        // NORECURENT char(1) — служебный параметр. Всегда передавать NULL
        await q.openCursor(
          sql: 'select MES, RESCODE, PRINTQUANT, ISACTION, R_IDSHTASK '
              'from PPRINT_PRINTADDART(?, ?, ?, ?, ?, ?, ?)',
          parameters: <Object?>[
            taskId,
            articleId,
            mobility.dbValue,
            printerName,
            null,
            null,
            printMode.dbValue,
          ],
        );
        final Map<String, dynamic>? row = await q.fetchOneAsMap();
        if (row == null) {
          throw Exception('PPRINT_PRINTADDART не вернула результат');
        }
        return PrintAddArtResult(
          message: _asString(row['MES']) ?? '',
          resultCode: _asInt(row['RESCODE']) ?? 0,
          printQuantity: _asInt(row['PRINTQUANT']) ?? 0,
          actionFlag:
              PriceTagActionFlag.fromDbValue(_asString(row['ISACTION'])),
          taskId: _asInt(row['R_IDSHTASK']) ?? 0,
        );
      } finally {
        await q.close();
      }
    });
  }

  /// (`PPRINT_PRINT`)
  ///
  /// Выпускает ценники на печать.
  ///
  /// - [taskId] - ID задания печати.
  ///
  /// - [reportId] - ID формы отчёта. `null` - печать по шаблону задания.
  ///
  /// - [printerName] - имя принтера. `null` - печать на принтере по умолчанию.
  ///
  /// - [copies] - количество копий. `null` - значение из задания или `1`.
  ///
  /// - [actionFlag] - фильтр по акционности. `null` - печать всех ценников.
  Future<PrintPriceTagsResult> printPriceTags({
    required int taskId,
    int? reportId,
    String? printerName,
    int? copies,
    PriceTagActionFlag? actionFlag,
  }) async {
    return _withReconnect(() async {
      final FbDb db = _requireDb();
      final FbQuery q = db.query();
      try {
        // Параметры 6 и 7 служебные. Всегда передавать NULL.
        await q.openCursor(
          sql:
              'select RES_CODE, RES_TEXT from PPRINT_PRINT(?, ?, ?, ?, ?, ?, ?)',
          parameters: <Object?>[
            taskId,
            reportId,
            printerName,
            copies,
            actionFlag?.dbValue,
            null,
            null,
          ],
        );
        final Map<String, dynamic>? row = await q.fetchOneAsMap();
        if (row == null) {
          throw Exception('PPRINT_PRINT не вернула результат');
        }
        return PrintPriceTagsResult(
          resultCode: _asInt(row['RES_CODE']) ?? 0,
          message: _asString(row['RES_TEXT']) ?? '',
        );
      } finally {
        await q.close();
      }
    });
  }

  Future<T> _withReconnect<T>(Future<T> Function() action) async {
    try {
      await open();
      if (_db == null) {
        throw Exception('Не удалось подключиться к БД.');
      }
      print('BDTO executing action...');
      return await action();
    } catch (error, st) {
      debugPrintFbDbException(error, st);
      final String? baseMessage = fbdbErrorMessage(error);
      if (!shouldReconnect(error)) {
        if (baseMessage != null) {
          throw Exception(baseMessage);
        }
        rethrow;
      }
      // TODO: Сейчас норм, но опасненько на будущее.
      // Если будут параллельные запросы, реконнект может
      // перекрыть активное соединение у другого запроса.
      try {
        // close крашит приложение, ыыыы.
        // await close();
        _db = null;
        await open();
        if (_db == null) {
          throw Exception('Не удалось подключиться к БД.');
        }
        return await action();
      } catch (retryError, retrySt) {
        // Пробуем переподключиться только один раз.
        // Провалилось - перебрасываем ошибку.
        // Если это будет ошибка соединения с БД,
        // то для UI будет готовый текст
        debugPrintFbDbException(retryError, retrySt);
        final String? message = fbdbErrorMessage(retryError) ?? baseMessage;
        if (message != null) {
          throw Exception(message);
        }
        rethrow;
      }
    }
  }

  /// Закрывает соединение с Firebird.
  Future<void> close() async {
    if (_db == null) {
      return;
    }
    print('BDTO closing connection...');
    await _db?.detach();
    print('BDTO closed connection');
    _db = null;
  }

  FbDb _requireDb() {
    final FbDb? db = _db;
    if (db == null) {
      throw StateError('База данных не подключена. Вызови open()');
    }
    return db;
  }

  String _requireEnv(String key) {
    final String? value = dotenv.env[key];
    if (value == null || value.trim().isEmpty) {
      throw StateError('$key не задан в энвах');
    }
    return _stripQuotes(value.trim());
  }

  String _stripQuotes(String value) {
    if (value.length >= 2) {
      final String first = value[0];
      final String last = value[value.length - 1];
      if ((first == "'" && last == "'") || (first == '"' && last == '"')) {
        return value.substring(1, value.length - 1);
      }
    }
    return value;
  }

  int? _asInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  double? _asDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  String? _asString(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    return value.toString();
  }
}
