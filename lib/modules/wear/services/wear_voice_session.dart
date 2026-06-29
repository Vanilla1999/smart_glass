import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_command_parser_service.dart';

class WearVoiceSession {
  WearVoiceSession._();

  static final WearVoiceSession I = WearVoiceSession._();

  bool get isListening =>
      WearDependencies.I.speechRecognitionService.isListening;

  Future<String> diagnostics() {
    return WearDependencies.I.speechRecognitionService.diagnostics();
  }

  Future<void> configureForScreen(WearScreenId screen) async {
    final bool freeText = _usesFreeTextRecognition(screen);
    await WearDependencies.I.speechRecognitionService.setRecognitionGrammar(
      freeText ? null : VoiceCommandParserService.grammarPhrases,
    );
  }

  Future<void> start() async {
    print('[WearVoiceSession] start requested, isListening=$isListening');
    if (isListening) {
      print('[WearVoiceSession] start skipped: ${await diagnostics()}');
      return;
    }
    try {
      await WearDependencies.I.ensureVoiceTypingPrepared();
      await WearDependencies.I.speechRecognitionService.startListening();
      print('[WearVoiceSession] started: ${await diagnostics()}');
    } catch (error, stackTrace) {
      print('[WearVoiceSession] start failed: $error\n$stackTrace');
    }
  }

  Future<void> stop() async {
    print('[WearVoiceSession] stop requested, isListening=$isListening');
    if (!isListening) {
      print('[WearVoiceSession] stop skipped: ${await diagnostics()}');
      return;
    }
    try {
      await WearDependencies.I.speechRecognitionService.stopListening();
      print('[WearVoiceSession] stopped: ${await diagnostics()}');
    } catch (error, stackTrace) {
      print('[WearVoiceSession] stop failed: $error\n$stackTrace');
    }
  }

  Future<void> restart({required String reason}) async {
    print('[WearVoiceSession] restart requested reason=$reason');
    try {
      await WearDependencies.I.ensureVoiceTypingPrepared();
      await WearDependencies.I.speechRecognitionService
          .restartListening(reason: reason);
      print('[WearVoiceSession] restarted: ${await diagnostics()}');
    } catch (error, stackTrace) {
      print('[WearVoiceSession] restart failed: $error\n$stackTrace');
    }
  }

  Future<void> ensureHealthy({required String reason}) async {
    final service = WearDependencies.I.speechRecognitionService;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int? lastAudioAt = service.lastAudioChunkAtMillis;
    final int? lastAudioAgeMs = lastAudioAt == null ? null : now - lastAudioAt;
    final int? lastNonSilentAudioAt = service.lastNonSilentAudioChunkAtMillis;
    final int? lastNonSilentAudioAgeMs =
        lastNonSilentAudioAt == null ? null : now - lastNonSilentAudioAt;
    print(
      '[WearVoiceSession] health-check reason=$reason '
      'isListening=${service.isListening} lastAudioAgeMs=$lastAudioAgeMs '
      'lastNonSilentAudioAgeMs=$lastNonSilentAudioAgeMs '
      'diagnostics=${await diagnostics()}',
    );

    if (!service.isListening) {
      await start();
      return;
    }

    if (lastAudioAgeMs == null || lastAudioAgeMs > 3000) {
      await restart(reason: '$reason staleAudioAgeMs=$lastAudioAgeMs');
    }
  }

  bool _usesFreeTextRecognition(WearScreenId screen) {
    return switch (screen) {
      WearScreenId.printerSelect ||
      WearScreenId.productSelect ||
      WearScreenId.availabilityGroup ||
      WearScreenId.availabilityProduct ||
      WearScreenId.availabilityFill ||
      WearScreenId.printCodeInput =>
        true,
      _ => false,
    };
  }
}
