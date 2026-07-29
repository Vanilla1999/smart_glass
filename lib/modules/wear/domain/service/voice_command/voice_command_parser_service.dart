import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_action_catalog.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';

class VoiceCommandParserService {
  VoiceCommandParserService({VoiceActionCatalog? catalog})
      : _catalog = catalog ?? VoiceActionCatalog();

  final VoiceActionCatalog _catalog;

  WearVoiceCommand? parseExactForScreen(WearScreenId screen, String text) {
    return _catalog.resolve(screen, text)?.command;
  }

  @Deprecated('Use parseExactForScreen so commands cannot escape the profile.')
  WearVoiceCommand? parseExact(String text) => null;
}
