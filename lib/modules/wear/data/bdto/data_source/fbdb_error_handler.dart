import 'package:fbdb/fbdb.dart';

void debugPrintFbDbException(Object error, StackTrace st) {
  print('BDTO DB error: ${error.runtimeType}: $error');
  if (error is FbServerException) {
    print('BDTO DB status vector: ${error.errors}');
    final List<int> gdsCodes = _extractGdsCodes(error.errors);
    final String formatted = gdsCodes
        .map((code) => '${_gdsName(code) ?? 'gds_$code'}($code)')
        .join(', ');
    if (formatted.isNotEmpty) {
      print('BDTO DB GDS codes: [$formatted]');
    }
  }
  print('BDTO DB stack trace:\n$st');
}

/// Показывает, что ошибка связана с соединением с БД и его можно пересоздать.
bool shouldReconnect(Object error) {
  if (error is FbClientException) {
    return true;
  }
  if (error is! FbServerException) {
    return false;
  }
  final List<int> gdsCodes = _extractGdsCodes(error.errors);
  return gdsCodes.any(_reconnectableCodes.contains);
}

String? fbdbErrorMessage(Object error) {
  if (error is FbClientException) {
    return 'Ошибка подключения к БД.';
  }
  if (error is! FbServerException) {
    return null;
  }
  for (final int code in _extractGdsCodes(error.errors)) {
    final String? message = _gdsName(code);
    if (message != null) {
      return message;
    }
  }
  return null;
}

List<int> _extractGdsCodes(List<int> statusVector) {
  // Короче говоря, ошибки идут тут в виде векторов.
  // У их значений есть определенный диапазон, который задается константами
  // ниже. А при ошибке приходит целый список значений, где не всё является
  // ошибкой.
  const int min = FbErrorCodes.isc_base;
  const int max = min + FbErrorCodes.isc_err_max;
  final List<int> result = [];
  for (final int value in statusVector) {
    if (value >= min && value <= max) {
      result.add(value);
    }
  }
  return result;
}

String? _gdsName(int code) => _gdsNames[code];

const Set<int> _reconnectableCodes = <int>{
  FbErrorCodes.isc_net_read_err,
  FbErrorCodes.isc_net_write_err,
  FbErrorCodes.isc_network_error,
  FbErrorCodes.isc_net_connect_err,
  FbErrorCodes.isc_connect_reject,
  FbErrorCodes.isc_lost_db_connection,
  FbErrorCodes.isc_att_shutdown,
  FbErrorCodes.isc_bad_db_handle,
};

const Map<int, String> _gdsNames = <int, String>{
  FbErrorCodes.isc_net_read_err: 'Ошибка чтения данных из соединения.',
  FbErrorCodes.isc_net_write_err: 'Ошибка записи данных в соединение.',
  FbErrorCodes.isc_network_error: 'Сетевая ошибка при работе с БД.',
  FbErrorCodes.isc_net_connect_err: 'Не удалось установить соединение с БД.',
  FbErrorCodes.isc_connect_reject: 'Соединение отклонено.',
  FbErrorCodes.isc_lost_db_connection: 'Соединение с БД потеряно.',
  FbErrorCodes.isc_att_shutdown: 'Соединение с БД закрыто.',
  FbErrorCodes.isc_bad_db_handle:
      'Плохая ручка БД (нет активного подключения).',
};
