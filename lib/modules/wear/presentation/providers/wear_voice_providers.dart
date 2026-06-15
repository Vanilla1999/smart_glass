import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';

final wearVoiceCommandsProvider = StreamProvider<WearVoiceCommand>((Ref ref) {
  final service = WearDependencies.I.voiceControlService;
  return service.commandStream;
});
