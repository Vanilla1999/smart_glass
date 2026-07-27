import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_action_catalog.dart';

class VoiceCommandParserService {
  static const Map<String, WearVoiceCommand> _exactCommandMap =
      <String, WearVoiceCommand>{
    'вверх': WearVoiceCommand.up,
    'верх': WearVoiceCommand.up,
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
    'тест фото': WearVoiceCommand.testPhoto,
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
    'прошлое страница': WearVoiceCommand.previousPage,
    'прошлую страницу': WearVoiceCommand.previousPage,
    'предыдущая страница': WearVoiceCommand.previousPage,
    'предыдущую страницу': WearVoiceCommand.previousPage,
    'страница назад': WearVoiceCommand.previousPage,
    'назад страница': WearVoiceCommand.previousPage,
    'стоп микрофон': WearVoiceCommand.stopMicrophone,
    'останови микрофон': WearVoiceCommand.stopMicrophone,
    'включи микрофон': WearVoiceCommand.startMicrophone,
    'включить микрофон': WearVoiceCommand.startMicrophone,
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
    'фонарик': WearVoiceCommand.flashlight,
    'включить фонарик': WearVoiceCommand.flashlight,
    'выключить фонарик': WearVoiceCommand.flashlight,
    'люмус максима': WearVoiceCommand.flashlight,
    'максима': WearVoiceCommand.flashlight,
  };

  static const Map<WearVoiceCommand, List<String>> _commandTokens =
      <WearVoiceCommand, List<String>>{
    WearVoiceCommand.up: <String>[
      'вверх',
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
      'прошлое страница',
      'прошлую страницу',
      'предыдущая страница',
      'предыдущую страницу',
      'страница назад',
      'назад страница',
    ],
    WearVoiceCommand.back: <String>['назад', 'вернуться', 'обратно'],
    WearVoiceCommand.home: <String>['домой', 'выход', 'главная'],
    WearVoiceCommand.finish: <String>[
      'завершить',
      'закончить',
      'готово',
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
    WearVoiceCommand.testPhoto: <String>['тест фото'],
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
    WearVoiceCommand.stopMicrophone: <String>[
      'стоп микрофон',
      'останови микрофон',
    ],
    WearVoiceCommand.startMicrophone: <String>[
      'включи микрофон',
      'включить микрофон',
    ],
  };

  static List<String> get grammarPhrases => <String>{
        ..._exactCommandMap.keys,
        ...VoiceActionCatalog().grammarPhrases,
      }.toList(growable: false);

  WearVoiceCommand? parseExact(String text) {
    final String normalized = _normalize(text);
    if (normalized.isEmpty) return null;
    return _exactCommandMap[normalized];
  }

  WearVoiceCommand? parse(String text) {
    final String normalized = _normalize(text);
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

  String _normalize(String text) {
    return text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zа-яё\s]'), '')
        .trim();
  }

  bool _containsToken(String text, String token) {
    return RegExp('(^|\\s)${RegExp.escape(token)}(\\s|\$)').hasMatch(text);
  }
}
