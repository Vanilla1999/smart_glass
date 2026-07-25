import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';

enum VoiceActivationPolicy { immediateExactPartial, finalOnly }

class VoiceActionEntry {
  const VoiceActionEntry({
    required this.command,
    required this.screens,
    required this.fullPhrases,
    required this.fastAliases,
    required this.activationPolicy,
  });

  final WearVoiceCommand command;
  final Set<WearScreenId> screens;
  final Set<String> fullPhrases;
  final Set<String> fastAliases;
  final VoiceActivationPolicy activationPolicy;
}

class VoiceActionCatalog {
  VoiceActionCatalog({List<VoiceActionEntry>? actions, this.revision = 1})
      : actions = actions ?? _defaultActions {
    _validate();
  }

  final List<VoiceActionEntry> actions;
  final int revision;

  Set<String> get grammarPhrases => <String>{
        for (final VoiceActionEntry action in actions) ...action.fullPhrases,
        for (final VoiceActionEntry action in actions) ...action.fastAliases,
      };

  WearVoiceCommand? resolveFastAlias(WearScreenId screen, String text) {
    final VoiceActionEntry? action = _resolve(
      screen,
      text,
      (VoiceActionEntry entry) =>
          entry.activationPolicy ==
              VoiceActivationPolicy.immediateExactPartial &&
          entry.fastAliases.contains(text),
    );
    return action?.command;
  }

  WearVoiceCommand? resolveFinal(WearScreenId screen, String text) {
    final VoiceActionEntry? action = _resolve(
      screen,
      text,
      (VoiceActionEntry entry) =>
          entry.fullPhrases.contains(text) || entry.fastAliases.contains(text),
    );
    return action?.command;
  }

  bool isKnownPhrase(String text) => grammarPhrases.contains(text);

  VoiceActionEntry? _resolve(
    WearScreenId screen,
    String text,
    bool Function(VoiceActionEntry entry) predicate,
  ) {
    final List<VoiceActionEntry> resolved =
        actions.where((VoiceActionEntry entry) {
      return entry.screens.contains(screen) && predicate(entry);
    }).toList(growable: false);
    if (resolved.length != 1) return null;
    return resolved.single;
  }

  void _validate() {
    for (final WearScreenId screen in WearScreenId.values) {
      final Set<String> aliases = <String>{};
      for (final VoiceActionEntry action in actions) {
        if (!action.screens.contains(screen) ||
            action.activationPolicy !=
                VoiceActivationPolicy.immediateExactPartial) {
          continue;
        }
        for (final String alias in action.fastAliases) {
          if (!aliases.add(alias)) {
            throw ArgumentError(
              'Duplicate fast voice alias "$alias" for screen $screen',
            );
          }
        }
      }
    }
  }

  static final List<VoiceActionEntry> _defaultActions = <VoiceActionEntry>[
    VoiceActionEntry(
      command: WearVoiceCommand.up,
      screens: WearScreenId.values.toSet(),
      fullPhrases: <String>{'вверх'},
      fastAliases: <String>{'вверх'},
      activationPolicy: VoiceActivationPolicy.immediateExactPartial,
    ),
    VoiceActionEntry(
      command: WearVoiceCommand.down,
      screens: WearScreenId.values.toSet(),
      fullPhrases: <String>{'вниз'},
      fastAliases: <String>{'вниз'},
      activationPolicy: VoiceActivationPolicy.immediateExactPartial,
    ),
    VoiceActionEntry(
      command: WearVoiceCommand.openPrintPriceTag,
      screens: <WearScreenId>{WearScreenId.menu},
      fullPhrases: <String>{'печать ценника', 'печать ценников'},
      fastAliases: <String>{'печать', 'ценник'},
      activationPolicy: VoiceActivationPolicy.immediateExactPartial,
    ),
    VoiceActionEntry(
      command: WearVoiceCommand.openAvailability,
      screens: <WearScreenId>{WearScreenId.menu},
      fullPhrases: <String>{'доступность'},
      fastAliases: <String>{'доступность'},
      activationPolicy: VoiceActivationPolicy.immediateExactPartial,
    ),
    VoiceActionEntry(
      command: WearVoiceCommand.openList,
      screens: <WearScreenId>{WearScreenId.availabilityInteraction},
      fullPhrases: <String>{'список товаров', 'открыть список'},
      fastAliases: <String>{'список', 'товары'},
      activationPolicy: VoiceActivationPolicy.immediateExactPartial,
    ),
    VoiceActionEntry(
      command: WearVoiceCommand.openDirectScan,
      screens: <WearScreenId>{WearScreenId.availabilityInteraction},
      fullPhrases: <String>{'прямое сканирование'},
      fastAliases: <String>{'прямое', 'сканирование'},
      activationPolicy: VoiceActivationPolicy.immediateExactPartial,
    ),
    VoiceActionEntry(
      command: WearVoiceCommand.print,
      screens: WearScreenId.values
          .where((WearScreenId screen) => screen != WearScreenId.menu)
          .toSet(),
      fullPhrases: <String>{'печать', 'напечатать'},
      fastAliases: <String>{},
      activationPolicy: VoiceActivationPolicy.finalOnly,
    ),
    VoiceActionEntry(
      command: WearVoiceCommand.takePhoto,
      screens: WearScreenId.values.toSet(),
      fullPhrases: <String>{'сделать фото', 'фото'},
      fastAliases: <String>{'фото'},
      activationPolicy: VoiceActivationPolicy.immediateExactPartial,
    ),
  ];
}
