import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_action_catalog.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_command_parser_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';

void main() {
  group('screen-scoped voice grammar', () {
    final VoiceActionCatalog catalog = VoiceActionCatalog();

    test('T01 menu contains only menu commands and unknown', () {
      final List<String> grammar = catalog.grammarFor(WearScreenId.menu);
      expect(
          grammar, containsAll(<String>['вверх', 'вниз', 'выбрать', '[unk]']));
      expect(grammar, isNot(contains('прямое')));
      expect(grammar, isNot(contains('фото')));
    });

    test('T02 availability interaction is scoped', () {
      final List<String> grammar =
          catalog.grammarFor(WearScreenId.availabilityInteraction);
      expect(
          grammar, containsAll(<String>['список', 'прямое', 'назад', '[unk]']));
      expect(grammar, isNot(contains('печать')));
      expect(grammar, isNot(contains('фото')));
    });

    test('T03 direct scan excludes unrelated actions', () {
      final List<String> grammar =
          catalog.grammarFor(WearScreenId.availabilityDirectScan);
      expect(grammar, containsAll(<String>['назад', 'фонарик', '[unk]']));
      expect(grammar, isNot(contains('фото')));
      expect(grammar, isNot(contains('печать')));
      expect(grammar, isNot(contains('доступность')));
    });

    test('T04 capability removes command without handler', () {
      expect(catalog.grammarFor(WearScreenId.help), <String>['назад', '[unk]']);
    });

    test('T04 runtime callback controls grammar membership', () {
      bool selectRegistered = false;
      final VoiceActionCatalog runtimeCatalog = VoiceActionCatalog(
        capabilities: VoiceScreenCapabilities(
          runtimeResolver: (WearScreenId screen, WearVoiceCommand command) {
            if (command == WearVoiceCommand.back) return true;
            return screen == WearScreenId.help &&
                command == WearVoiceCommand.select &&
                selectRegistered;
          },
        ),
      );

      expect(runtimeCatalog.grammarFor(WearScreenId.help),
          isNot(contains('выбрать')));
      selectRegistered = true;
      expect(runtimeCatalog.grammarFor(WearScreenId.help), contains('выбрать'));
    });

    test('T05 parser cannot execute outside active profile', () {
      final VoiceCommandParserService parser =
          VoiceCommandParserService(catalog: catalog);
      expect(
        parser.parseExactForScreen(WearScreenId.menu, 'прямое'),
        isNull,
      );
      expect(
        parser.parseExactForScreen(
          WearScreenId.availabilityInteraction,
          'прямое',
        ),
        WearVoiceCommand.openDirectScan,
      );
    });

    test('T06 duplicate alias fails validation', () {
      expect(
        () => VoiceActionCatalog(actions: <VoiceActionEntry>[
          VoiceActionEntry(
            command: WearVoiceCommand.openList,
            screens: <WearScreenId>{WearScreenId.menu},
            fullPhrases: <String>{'список'},
            fastAliases: <String>{'команда'},
            activationPolicy: VoiceActivationPolicy.stableExactPartial,
          ),
          VoiceActionEntry(
            command: WearVoiceCommand.openHelp,
            screens: <WearScreenId>{WearScreenId.menu},
            fullPhrases: <String>{'помощь'},
            fastAliases: <String>{'команда'},
            activationPolicy: VoiceActivationPolicy.stableExactPartial,
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('T07 fast alias prefix collision fails validation', () {
      expect(
        () => VoiceActionCatalog(actions: <VoiceActionEntry>[
          VoiceActionEntry(
            command: WearVoiceCommand.back,
            screens: <WearScreenId>{WearScreenId.availabilityProduct},
            fullPhrases: <String>{'назад'},
            fastAliases: <String>{'назад'},
            activationPolicy: VoiceActivationPolicy.stableExactPartial,
          ),
          VoiceActionEntry(
            command: WearVoiceCommand.previousPage,
            screens: <WearScreenId>{WearScreenId.availabilityProduct},
            fullPhrases: <String>{'назад страница'},
            fastAliases: <String>{},
            activationPolicy: VoiceActivationPolicy.endpointOnly,
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('unknown feature flag can exclude unknown token', () {
      expect(
        VoiceActionCatalog(includeUnknown: false).grammarFor(WearScreenId.menu),
        isNot(contains('[unk]')),
      );
    });

    test('T30 root menu grammar cannot execute back', () {
      expect(catalog.grammarFor(WearScreenId.menu), isNot(contains('назад')));
      expect(catalog.resolve(WearScreenId.menu, 'назад'), isNull);
    });
  });
}
