import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';

class VoiceCommandParserService {
  static const Map<String, WearVoiceCommand> _exactCommandMap =
      <String, WearVoiceCommand>{
    'вверх': WearVoiceCommand.up,
    'верх': WearVoiceCommand.up,
    'бер': WearVoiceCommand.up,
    'сбер': WearVoiceCommand.up,
    'наверх': WearVoiceCommand.up,
    'на верх': WearVoiceCommand.up,
    'выше': WearVoiceCommand.up,
    'подними': WearVoiceCommand.up,
    'поднять': WearVoiceCommand.up,
    'листай вверх': WearVoiceCommand.up,
    'вниз': WearVoiceCommand.down,
    'низ': WearVoiceCommand.down,
    'в низ': WearVoiceCommand.down,
    'ниже': WearVoiceCommand.down,
    'опусти': WearVoiceCommand.down,
    'опустить': WearVoiceCommand.down,
    'листай вниз': WearVoiceCommand.down,
    'выбрать': WearVoiceCommand.select,
    'выбери': WearVoiceCommand.select,
    'выбор': WearVoiceCommand.select,
    'ок': WearVoiceCommand.select,
    'окей': WearVoiceCommand.select,
    'подтвердить': WearVoiceCommand.select,
    'подтверди': WearVoiceCommand.select,
    'принять': WearVoiceCommand.select,
    'прими': WearVoiceCommand.select,
    'нажать': WearVoiceCommand.select,
    'нажми': WearVoiceCommand.select,
    'печать ценника': WearVoiceCommand.openPrintPriceTag,
    'печать ценников': WearVoiceCommand.openPrintPriceTag,
    'доступность': WearVoiceCommand.openAvailability,
    'справка': WearVoiceCommand.openHelp,
    'настройки': WearVoiceCommand.openSettings,
    'подключить': WearVoiceCommand.connectScanner,
    'подключить кольцо': WearVoiceCommand.connectScanner,
    'сменить пользователя': WearVoiceCommand.switchUser,
    'настройки бд': WearVoiceCommand.openDbSettings,
    'настройки базы': WearVoiceCommand.openDbSettings,
    'наполнить базу': WearVoiceCommand.fillDatabase,
    'продолжить': WearVoiceCommand.continueScan,
    'ручной ввод': WearVoiceCommand.manualInput,
    'напечатать': WearVoiceCommand.print,
    'печать': WearVoiceCommand.print,
    'сделать фото': WearVoiceCommand.takePhoto,
    'фото': WearVoiceCommand.takePhoto,
    'к списку': WearVoiceCommand.backToList,
    'список': WearVoiceCommand.openList,
    'прямое сканирование': WearVoiceCommand.openDirectScan,
    'очистить': WearVoiceCommand.clear,
    'сохранить': WearVoiceCommand.save,
    'начать работу': WearVoiceCommand.select,
    'да': WearVoiceCommand.yes,
    'ага': WearVoiceCommand.yes,
    'верно': WearVoiceCommand.yes,
    'правильно': WearVoiceCommand.yes,
    'есть': WearVoiceCommand.yes,
    'нет': WearVoiceCommand.no,
    'не': WearVoiceCommand.no,
    'отмена': WearVoiceCommand.cancel,
    'отменить': WearVoiceCommand.cancel,
    'закрыть': WearVoiceCommand.cancel,
    'закрой': WearVoiceCommand.cancel,
    'следующая страница': WearVoiceCommand.nextPage,
    'дальше': WearVoiceCommand.nextPage,
    'далее': WearVoiceCommand.nextPage,
    'прошлая страница': WearVoiceCommand.previousPage,
    'предыдущая страница': WearVoiceCommand.previousPage,
    'страница назад': WearVoiceCommand.previousPage,
    'назад страница': WearVoiceCommand.previousPage,
    'не надо': WearVoiceCommand.no,
    'назад': WearVoiceCommand.back,
    'вернуться': WearVoiceCommand.back,
    'обратно': WearVoiceCommand.back,
    'выход': WearVoiceCommand.home,
    'домой': WearVoiceCommand.home,
    'дом': WearVoiceCommand.home,
    'главная': WearVoiceCommand.home,
    'в меню': WearVoiceCommand.home,
    'завершить': WearVoiceCommand.finish,
    'закончить': WearVoiceCommand.finish,
    'готово': WearVoiceCommand.finish,
    'стоп': WearVoiceCommand.finish,
    'конец': WearVoiceCommand.finish,
    'фонарик': WearVoiceCommand.flashlight,
    'включить фонарик': WearVoiceCommand.flashlight,
    'выключить фонарик': WearVoiceCommand.flashlight,
  };

  static const Map<WearVoiceCommand, List<String>> _commandTokens =
      <WearVoiceCommand, List<String>>{
    WearVoiceCommand.up: <String>[
      'вверх',
      'бер',
      'сбер',
      'наверх',
      'выше',
      'подними',
      'поднять',
    ],
    WearVoiceCommand.down: <String>[
      'вниз',
      'ниже',
      'опусти',
      'опустить',
    ],
    WearVoiceCommand.select: <String>[
      'выбрать',
      'выбери',
      'ок',
      'окей',
      'подтвердить',
      'подтверди',
      'принять',
      'прими',
      'нажать',
      'нажми',
    ],
    WearVoiceCommand.yes: <String>['да', 'ага', 'верно', 'правильно', 'есть'],
    WearVoiceCommand.no: <String>['нет'],
    WearVoiceCommand.previousPage: <String>[
      'прошлая страница',
      'предыдущая страница',
      'страница назад',
      'назад страница',
    ],
    WearVoiceCommand.back: <String>['назад', 'вернуться', 'обратно'],
    WearVoiceCommand.home: <String>['домой', 'выход', 'главная'],
    WearVoiceCommand.finish: <String>[
      'завершить',
      'закончить',
      'готово',
      'стоп',
      'конец',
    ],
    WearVoiceCommand.flashlight: <String>['фонарик'],
    WearVoiceCommand.openPrintPriceTag: <String>['печать ценника'],
    WearVoiceCommand.openAvailability: <String>['доступность'],
    WearVoiceCommand.openHelp: <String>['справка'],
    WearVoiceCommand.openSettings: <String>['настройки'],
    WearVoiceCommand.connectScanner: <String>[
      'подключить',
      'подключить кольцо'
    ],
    WearVoiceCommand.switchUser: <String>['сменить пользователя'],
    WearVoiceCommand.openDbSettings: <String>['настройки бд', 'настройки базы'],
    WearVoiceCommand.fillDatabase: <String>['наполнить базу'],
    WearVoiceCommand.continueScan: <String>['продолжить'],
    WearVoiceCommand.manualInput: <String>['ручной ввод'],
    WearVoiceCommand.print: <String>['напечатать', 'печать'],
    WearVoiceCommand.takePhoto: <String>['сделать фото', 'фото'],
    WearVoiceCommand.backToList: <String>['к списку'],
    WearVoiceCommand.openList: <String>['список'],
    WearVoiceCommand.openDirectScan: <String>['прямое сканирование'],
    WearVoiceCommand.clear: <String>['очистить'],
    WearVoiceCommand.save: <String>['сохранить'],
    WearVoiceCommand.cancel: <String>[
      'отмена',
      'отменить',
      'закрыть',
      'закрой'
    ],
    WearVoiceCommand.nextPage: <String>[
      'следующая страница',
      'дальше',
      'далее',
    ],
  };

  static List<String> get grammarPhrases => _exactCommandMap.keys.toList();

  WearVoiceCommand? parse(String text) {
    final String normalized = text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zа-яё\s]'), '')
        .trim();
    print('[VoiceCommandParser] raw="$text" normalized="$normalized"');
    if (normalized.isEmpty) return null;
    final WearVoiceCommand? exact = _exactCommandMap[normalized];
    if (exact != null) {
      print('[VoiceCommandParser] exact match parsed=$exact');
      return exact;
    }

    WearVoiceCommand? cmd;
    String? matchedToken;
    for (final MapEntry<WearVoiceCommand, List<String>> entry
        in _commandTokens.entries) {
      for (final String token in entry.value) {
        if (!_containsToken(normalized, token)) {
          continue;
        }
        cmd = entry.key;
        matchedToken = token;
        break;
      }
      if (cmd != null) break;
    }
    if (cmd == null) {
      print('[VoiceCommandParser] no command token matched');
    } else {
      print('[VoiceCommandParser] token="$matchedToken" parsed=$cmd');
    }
    return cmd;
  }

  bool _containsToken(String text, String token) {
    return RegExp('(^|\\s)${RegExp.escape(token)}(\\s|\$)').hasMatch(text);
  }
}
