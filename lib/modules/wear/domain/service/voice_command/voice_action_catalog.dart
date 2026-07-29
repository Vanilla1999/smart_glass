import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';

enum VoiceActivationPolicy {
  immediateExactPartial,
  stableExactPartial,
  endpointOnly,
}

enum VoiceActionRisk { navigation, stateChange, destructive }

enum CommandGrammarProfile {
  menu,
  availabilityInteraction,
  list,
  directScan,
  selection,
  confirmation,
  settings,
}

class VoiceActionEntry {
  VoiceActionEntry({
    required this.command,
    required Set<WearScreenId> screens,
    required Set<String> fullPhrases,
    required Set<String> fastAliases,
    required this.activationPolicy,
    this.risk = VoiceActionRisk.navigation,
  })  : screens = Set<WearScreenId>.unmodifiable(screens),
        fullPhrases = Set<String>.unmodifiable(fullPhrases),
        fastAliases = Set<String>.unmodifiable(fastAliases);

  final WearVoiceCommand command;
  final Set<WearScreenId> screens;
  final Set<String> fullPhrases;
  final Set<String> fastAliases;
  final VoiceActivationPolicy activationPolicy;
  final VoiceActionRisk risk;
}

typedef VoiceCapabilityResolver = bool Function(
  WearScreenId screen,
  WearVoiceCommand command,
);

class VoiceScreenCapabilities {
  const VoiceScreenCapabilities({this.runtimeResolver});

  final VoiceCapabilityResolver? runtimeResolver;

  bool canHandle(WearScreenId screen, WearVoiceCommand command) {
    final VoiceCapabilityResolver? resolver = runtimeResolver;
    if (resolver != null) return resolver(screen, command);
    return _commandsByScreen[screen]?.contains(command) ?? false;
  }

  static const Set<WearVoiceCommand> _listNavigation = <WearVoiceCommand>{
    WearVoiceCommand.up,
    WearVoiceCommand.down,
    WearVoiceCommand.select,
    WearVoiceCommand.back,
    WearVoiceCommand.home,
  };

  static const Map<WearScreenId, Set<WearVoiceCommand>> _commandsByScreen =
      <WearScreenId, Set<WearVoiceCommand>>{
    WearScreenId.menu: <WearVoiceCommand>{
      WearVoiceCommand.up,
      WearVoiceCommand.down,
      WearVoiceCommand.select,
      WearVoiceCommand.openPrintPriceTag,
      WearVoiceCommand.openAvailability,
      WearVoiceCommand.openHelp,
      WearVoiceCommand.openSettings,
    },
    WearScreenId.availabilityInteraction: <WearVoiceCommand>{
      ..._listNavigation,
      WearVoiceCommand.openList,
      WearVoiceCommand.openDirectScan,
    },
    WearScreenId.availabilityGroup: _listNavigation,
    WearScreenId.availabilityProduct: <WearVoiceCommand>{
      ..._listNavigation,
      WearVoiceCommand.nextPage,
      WearVoiceCommand.previousPage,
    },
    WearScreenId.productSelect: _listNavigation,
    WearScreenId.printerSelect: _listNavigation,
    WearScreenId.availabilityDirectScan: <WearVoiceCommand>{
      WearVoiceCommand.back,
      WearVoiceCommand.home,
      WearVoiceCommand.flashlight,
      WearVoiceCommand.takePhoto,
    },
    WearScreenId.homeConfirm: <WearVoiceCommand>{
      WearVoiceCommand.yes,
      WearVoiceCommand.no,
      WearVoiceCommand.back,
    },
    WearScreenId.continueScan: <WearVoiceCommand>{
      WearVoiceCommand.up,
      WearVoiceCommand.down,
      WearVoiceCommand.select,
      WearVoiceCommand.back,
    },
    WearScreenId.help: <WearVoiceCommand>{WearVoiceCommand.back},
    WearScreenId.settings: <WearVoiceCommand>{WearVoiceCommand.back},
    WearScreenId.dbSettings: <WearVoiceCommand>{
      WearVoiceCommand.save,
      WearVoiceCommand.back,
    },
    WearScreenId.wifiSettings: <WearVoiceCommand>{WearVoiceCommand.back},
    WearScreenId.printerSettings: <WearVoiceCommand>{WearVoiceCommand.back},
  };
}

class VoiceActionCatalog {
  VoiceActionCatalog({
    List<VoiceActionEntry>? actions,
    VoiceScreenCapabilities? capabilities,
    this.includeUnknown = true,
  })  : actions =
            List<VoiceActionEntry>.unmodifiable(actions ?? _defaultActions),
        capabilities = capabilities ?? const VoiceScreenCapabilities() {
    validate();
  }

  final List<VoiceActionEntry> actions;
  final VoiceScreenCapabilities capabilities;
  final bool includeUnknown;

  CommandGrammarProfile profileFor(WearScreenId screen) => switch (screen) {
        WearScreenId.menu => CommandGrammarProfile.menu,
        WearScreenId.availabilityInteraction =>
          CommandGrammarProfile.availabilityInteraction,
        WearScreenId.availabilityGroup ||
        WearScreenId.availabilityProduct =>
          CommandGrammarProfile.list,
        WearScreenId.availabilityDirectScan => CommandGrammarProfile.directScan,
        WearScreenId.homeConfirm => CommandGrammarProfile.confirmation,
        WearScreenId.settings ||
        WearScreenId.dbSettings ||
        WearScreenId.wifiSettings ||
        WearScreenId.printerSettings =>
          CommandGrammarProfile.settings,
        _ => CommandGrammarProfile.selection,
      };

  List<String> grammarFor(WearScreenId screen) {
    final Set<String> phrases = <String>{};
    for (final VoiceActionEntry action in actionsFor(screen)) {
      phrases
        ..addAll(action.fullPhrases)
        ..addAll(action.fastAliases);
    }
    if (includeUnknown) phrases.add('[unk]');
    return List<String>.unmodifiable(phrases);
  }

  Iterable<VoiceActionEntry> actionsFor(WearScreenId screen) sync* {
    for (final VoiceActionEntry action in actions) {
      if (action.screens.contains(screen) &&
          capabilities.canHandle(screen, action.command)) {
        yield action;
      }
    }
  }

  VoiceActionEntry? resolve(WearScreenId screen, String text) {
    final String normalized = normalize(text);
    if (normalized.isEmpty || normalized == '[unk]') return null;
    final List<VoiceActionEntry> matches = actionsFor(screen).where((entry) {
      return entry.fullPhrases.contains(normalized) ||
          entry.fastAliases.contains(normalized);
    }).toList(growable: false);
    return matches.length == 1 ? matches.single : null;
  }

  VoiceActionEntry? resolvePartial(WearScreenId screen, String text) {
    final String normalized = normalize(text);
    final VoiceActionEntry? entry = resolve(screen, normalized);
    return entry != null && entry.fastAliases.contains(normalized)
        ? entry
        : null;
  }

  WearVoiceCommand? resolveFastAlias(WearScreenId screen, String text) =>
      resolvePartial(screen, text)?.command;

  void validate() {
    const Set<String> unsafeGlobalAliases = <String>{
      'не',
      'есть',
      'дом',
      'выход',
      'готово',
    };
    for (final WearScreenId screen in WearScreenId.values) {
      final Map<String, WearVoiceCommand> aliases =
          <String, WearVoiceCommand>{};
      final List<VoiceActionEntry> screenActions = actions
          .where((VoiceActionEntry action) => action.screens.contains(screen))
          .toList();
      for (final VoiceActionEntry action in screenActions) {
        for (final String alias in action.fastAliases) {
          if (unsafeGlobalAliases.contains(alias)) {
            throw ArgumentError('Unsafe fast voice alias "$alias"');
          }
          final WearVoiceCommand? existing = aliases[alias];
          if (existing != null && existing != action.command) {
            throw ArgumentError(
              'Duplicate fast voice alias "$alias" for screen $screen',
            );
          }
          aliases[alias] = action.command;
        }
      }
      for (final MapEntry<String, WearVoiceCommand> alias in aliases.entries) {
        for (final VoiceActionEntry action in screenActions) {
          for (final String phrase in action.fullPhrases) {
            if (action.command != alias.value &&
                phrase.startsWith('${alias.key} ')) {
              throw ArgumentError(
                'Fast alias prefix collision "${alias.key}" -> "$phrase" '
                'for screen $screen',
              );
            }
          }
        }
      }
    }
  }

  static String normalize(String text) => text
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-zа-яё\[\]\s]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static final List<VoiceActionEntry> _defaultActions = <VoiceActionEntry>[
    _action(WearVoiceCommand.up, 'вверх',
        VoiceActivationPolicy.immediateExactPartial,
        screens: _selectableScreens, aliases: <String>{'вверх'}),
    _action(WearVoiceCommand.down, 'вниз',
        VoiceActivationPolicy.immediateExactPartial,
        screens: _selectableScreens, aliases: <String>{'вниз'}),
    _action(
        WearVoiceCommand.select, 'выбрать', VoiceActivationPolicy.endpointOnly,
        screens: _selectableScreens),
    _action(WearVoiceCommand.back, 'назад',
        VoiceActivationPolicy.stableExactPartial,
        screens: _backScreens, aliases: <String>{'назад'}),
    _action(WearVoiceCommand.home, 'домой',
        VoiceActivationPolicy.stableExactPartial,
        screens: <WearScreenId>{
          WearScreenId.availabilityInteraction,
          WearScreenId.availabilityGroup,
          WearScreenId.availabilityProduct,
          WearScreenId.availabilityDirectScan
        }),
    _action(WearVoiceCommand.openPrintPriceTag, 'печать ценников',
        VoiceActivationPolicy.endpointOnly,
        screens: <WearScreenId>{WearScreenId.menu},
        phrases: <String>{'печать', 'печать ценника', 'печать ценников'}),
    _action(WearVoiceCommand.openAvailability, 'доступность',
        VoiceActivationPolicy.stableExactPartial,
        screens: <WearScreenId>{WearScreenId.menu},
        aliases: <String>{'доступность'}),
    _action(WearVoiceCommand.openHelp, 'справка',
        VoiceActivationPolicy.stableExactPartial,
        screens: <WearScreenId>{WearScreenId.menu},
        aliases: <String>{'справка'}),
    _action(WearVoiceCommand.openSettings, 'настройки',
        VoiceActivationPolicy.stableExactPartial,
        screens: <WearScreenId>{WearScreenId.menu},
        aliases: <String>{'настройки'}),
    _action(WearVoiceCommand.openList, 'список товаров',
        VoiceActivationPolicy.stableExactPartial,
        screens: <WearScreenId>{WearScreenId.availabilityInteraction},
        phrases: <String>{'список', 'список товаров'},
        aliases: <String>{'список'}),
    _action(WearVoiceCommand.openDirectScan, 'прямое сканирование',
        VoiceActivationPolicy.stableExactPartial,
        screens: <WearScreenId>{WearScreenId.availabilityInteraction},
        phrases: <String>{'прямое', 'прямое сканирование'},
        aliases: <String>{'прямое'}),
    _action(WearVoiceCommand.nextPage, 'следующая страница',
        VoiceActivationPolicy.endpointOnly,
        screens: <WearScreenId>{
          WearScreenId.availabilityGroup,
          WearScreenId.availabilityProduct,
          WearScreenId.productSelect,
        }),
    _action(WearVoiceCommand.previousPage, 'предыдущая страница',
        VoiceActivationPolicy.endpointOnly,
        screens: <WearScreenId>{
          WearScreenId.availabilityGroup,
          WearScreenId.availabilityProduct,
          WearScreenId.productSelect,
        },
        phrases: <String>{
          'предыдущая страница',
          'прошлая страница'
        }),
    _action(WearVoiceCommand.flashlight, 'фонарик',
        VoiceActivationPolicy.stableExactPartial,
        screens: <WearScreenId>{WearScreenId.availabilityDirectScan},
        aliases: <String>{'фонарик'}),
    _action(WearVoiceCommand.takePhoto, 'сделать фото',
        VoiceActivationPolicy.endpointOnly,
        screens: <WearScreenId>{WearScreenId.availabilityCheck},
        phrases: <String>{'фото', 'сделать фото'}),
    _action(WearVoiceCommand.yes, 'да', VoiceActivationPolicy.endpointOnly,
        screens: <WearScreenId>{
          WearScreenId.homeConfirm,
          WearScreenId.availabilityCheck,
        }),
    _action(WearVoiceCommand.no, 'нет', VoiceActivationPolicy.endpointOnly,
        screens: <WearScreenId>{
          WearScreenId.homeConfirm,
          WearScreenId.availabilityCheck,
        }),
    _action(WearVoiceCommand.manualInput, 'ручной ввод',
        VoiceActivationPolicy.endpointOnly,
        screens: <WearScreenId>{
          WearScreenId.availabilityDirectScan,
          WearScreenId.availabilityCheck,
          WearScreenId.availabilityFill,
        }),
    _action(
        WearVoiceCommand.print, 'печать', VoiceActivationPolicy.endpointOnly,
        screens: <WearScreenId>{WearScreenId.availabilityCheck}),
    _action(WearVoiceCommand.backToList, 'к списку',
        VoiceActivationPolicy.endpointOnly,
        screens: <WearScreenId>{WearScreenId.availabilityCheck}),
    _action(
        WearVoiceCommand.clear, 'очистить', VoiceActivationPolicy.endpointOnly,
        screens: <WearScreenId>{WearScreenId.availabilityFill}),
    _action(
        WearVoiceCommand.cancel, 'отмена', VoiceActivationPolicy.endpointOnly,
        screens: <WearScreenId>{WearScreenId.productSelect}),
    _action(WearVoiceCommand.continueScan, 'продолжить',
        VoiceActivationPolicy.endpointOnly,
        screens: <WearScreenId>{WearScreenId.continueScan}),
    _action(WearVoiceCommand.finish, 'завершить',
        VoiceActivationPolicy.endpointOnly,
        screens: <WearScreenId>{WearScreenId.continueScan}),
    _action(
        WearVoiceCommand.save, 'сохранить', VoiceActivationPolicy.endpointOnly,
        screens: <WearScreenId>{WearScreenId.dbSettings},
        risk: VoiceActionRisk.stateChange),
  ];

  static const Set<WearScreenId> _selectableScreens = <WearScreenId>{
    WearScreenId.menu,
    WearScreenId.availabilityInteraction,
    WearScreenId.availabilityGroup,
    WearScreenId.availabilityProduct,
    WearScreenId.productSelect,
    WearScreenId.printerSelect,
    WearScreenId.continueScan,
    WearScreenId.help,
    WearScreenId.settings,
    WearScreenId.wifiSettings,
    WearScreenId.printerSettings,
    WearScreenId.availabilityCheck,
    WearScreenId.availabilityDirectScan,
    WearScreenId.availabilityFill,
  };

  static const Set<WearScreenId> _backScreens = <WearScreenId>{
    WearScreenId.availabilityInteraction,
    WearScreenId.availabilityGroup,
    WearScreenId.availabilityProduct,
    WearScreenId.productSelect,
    WearScreenId.printerSelect,
    WearScreenId.availabilityDirectScan,
    WearScreenId.homeConfirm,
    WearScreenId.continueScan,
    WearScreenId.help,
    WearScreenId.settings,
    WearScreenId.dbSettings,
    WearScreenId.wifiSettings,
    WearScreenId.printerSettings,
    WearScreenId.scanIdle,
    WearScreenId.availabilityCheck,
    WearScreenId.availabilityFill,
  };

  static VoiceActionEntry _action(
    WearVoiceCommand command,
    String phrase,
    VoiceActivationPolicy policy, {
    required Set<WearScreenId> screens,
    Set<String>? phrases,
    Set<String> aliases = const <String>{},
    VoiceActionRisk risk = VoiceActionRisk.navigation,
  }) {
    return VoiceActionEntry(
      command: command,
      screens: screens,
      fullPhrases: phrases ?? <String>{phrase},
      fastAliases: aliases,
      activationPolicy: policy,
      risk: risk,
    );
  }
}
