import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';

class WearVoiceSession {
  WearVoiceSession._();

  static final WearVoiceSession I = WearVoiceSession._();

  bool get isListening => WearDependencies.I.speechRecognitionService.isListening;

  Future<void> start() async {
    if (isListening) return;
    try {
      await WearDependencies.I.speechRecognitionService.startListening();
      print('[WearVoiceSession] started');
    } catch (error, stackTrace) {
      print('[WearVoiceSession] start failed: $error\n$stackTrace');
    }
  }

  Future<void> stop() async {
    if (!isListening) return;
    try {
      await WearDependencies.I.speechRecognitionService.stopListening();
      print('[WearVoiceSession] stopped');
    } catch (error, stackTrace) {
      print('[WearVoiceSession] stop failed: $error\n$stackTrace');
    }
  }
}
