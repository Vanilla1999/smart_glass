import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_action_catalog.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_command_parser_service.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';

void main() {
  group('screen-scoped voice grammar', () {
    final VoiceActionCatalog catalog = VoiceActionCatalog();

    test('menu contains only menu commands and unknown', () {
      final List<String> grammar = catalog.grammarFor(WearScreenId.menu);
      expect(
          grammar, containsAll(<String>['вверх', 'вниз', 'выбрать', '[unk]']));
      expect(grammar, isNot(contains('прямое')));
      expect(grammar, isNot(contains('фото')));
    });

    test('T01 only up and down use production partial activation', () {
      for (final VoiceActionEntry action in catalog.actions) {
        if (<WearVoiceCommand>{
          WearVoiceCommand.up,
          WearVoiceCommand.down,
        }.contains(action.command)) {
          expect(
            action.activationPolicy,
            VoiceActivationPolicy.immediateExactPartial,
            reason: '${action.command} must remain immediate',
          );
        } else {
          expect(
            action.activationPolicy,
            VoiceActivationPolicy.endpointOnly,
            reason: '${action.command} must wait for an endpoint',
          );
        }
        expect(
          action.activationPolicy,
          isNot(VoiceActivationPolicy.stableExactPartial),
        );
      }
    });

    test('partial activation outside the explicit allowlist is rejected', () {
      expect(
        () => VoiceActionCatalog(actions: <VoiceActionEntry>[
          VoiceActionEntry(
            command: WearVoiceCommand.openAvailability,
            screens: <WearScreenId>{WearScreenId.menu},
            fullPhrases: <String>{'доступность'},
            fastAliases: <String>{'доступность'},
            activationPolicy: VoiceActivationPolicy.stableExactPartial,
          ),
        ]),
        throwsArgumentError,
      );
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

    test('flashlight is available on every screen', () {
      final VoiceCommandParserService parser =
          VoiceCommandParserService(catalog: catalog);

      for (final WearScreenId screen in WearScreenId.values) {
        expect(
          parser.parseExactForScreen(screen, 'фонарик'),
          WearVoiceCommand.flashlight,
          reason: 'Flashlight unavailable on ${screen.name}',
        );
      }
    });

    test('T04 capability removes command without handler', () {
      expect(catalog.grammarFor(WearScreenId.help), <String>[
        'назад',
        'домой',
        'фонарик',
        'выключить микрофон',
        'стоп микрофон',
        'включить микрофон',
        'старт микрофон',
        '[unk]',
      ]);
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

    test('clarification grammar includes page navigation commands', () {
      final VoiceCommandParserService parser =
          VoiceCommandParserService(catalog: catalog);

      expect(
        parser.parseExactForScreen(
          WearScreenId.voiceClarification,
          'следующая страница',
        ),
        WearVoiceCommand.nextPage,
      );
      expect(
        parser.parseExactForScreen(
          WearScreenId.voiceClarification,
          'прошлая страница',
        ),
        WearVoiceCommand.previousPage,
      );
    });

    test('printer grammar includes page navigation and home commands', () {
      expect(
        catalog.grammarFor(WearScreenId.printerSelect),
        containsAll(<String>[
          'домой',
          'следующая страница',
          'предыдущая страница',
        ]),
      );
      expect(
        VoiceCommandParserService(catalog: catalog).parseExactForScreen(
          WearScreenId.printerSelect,
          'домой',
        ),
        WearVoiceCommand.home,
      );
    });

    test('home confirmation supports focus navigation and selection', () {
      final VoiceCommandParserService parser =
          VoiceCommandParserService(catalog: catalog);

      expect(
        parser.parseExactForScreen(WearScreenId.homeConfirm, 'вверх'),
        WearVoiceCommand.up,
      );
      expect(
        parser.parseExactForScreen(WearScreenId.homeConfirm, 'вниз'),
        WearVoiceCommand.down,
      );
      expect(
        parser.parseExactForScreen(WearScreenId.homeConfirm, 'выбрать'),
        WearVoiceCommand.select,
      );
    });

    test('home is available on every screen outside the home flow', () {
      final VoiceCommandParserService parser =
          VoiceCommandParserService(catalog: catalog);

      for (final WearScreenId screen in WearScreenId.values) {
        final bool isHomeFlow =
            screen == WearScreenId.menu || screen == WearScreenId.homeConfirm;
        expect(
          parser.parseExactForScreen(screen, 'домой'),
          isHomeFlow ? isNull : WearVoiceCommand.home,
          reason: 'Unexpected home command availability on ${screen.name}',
        );
      }
    });

    test('T06 duplicate alias fails validation', () {
      expect(
        () => VoiceActionCatalog(actions: <VoiceActionEntry>[
          VoiceActionEntry(
            command: WearVoiceCommand.openList,
            screens: <WearScreenId>{WearScreenId.menu},
            fullPhrases: <String>{'список'},
            fastAliases: <String>{'команда'},
            activationPolicy: VoiceActivationPolicy.endpointOnly,
          ),
          VoiceActionEntry(
            command: WearVoiceCommand.openHelp,
            screens: <WearScreenId>{WearScreenId.menu},
            fullPhrases: <String>{'помощь'},
            fastAliases: <String>{'команда'},
            activationPolicy: VoiceActivationPolicy.endpointOnly,
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

    test('microphone commands are endpoint-only on every screen', () {
      for (final WearScreenId screen in WearScreenId.values) {
        expect(
          catalog.resolve(screen, 'выключить микрофон')?.command,
          WearVoiceCommand.stopMicrophone,
        );
        expect(
          catalog.resolve(screen, 'включить микрофон')?.command,
          WearVoiceCommand.startMicrophone,
        );
        expect(
          catalog.resolve(screen, 'стоп микрофон')?.command,
          WearVoiceCommand.stopMicrophone,
        );
        expect(
          catalog.resolve(screen, 'старт микрофон')?.command,
          WearVoiceCommand.startMicrophone,
        );
        expect(
          catalog.resolvePartial(screen, 'выключить микрофон'),
          isNull,
        );
        expect(catalog.resolvePartial(screen, 'включить микрофон'), isNull);
        expect(catalog.resolvePartial(screen, 'стоп микрофон'), isNull);
        expect(catalog.resolvePartial(screen, 'старт микрофон'), isNull);
      }
    });
  });
}
