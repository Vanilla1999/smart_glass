/// Voice recognition state
sealed class VoiceState {
  const VoiceState();
}

/// Voice recognition is idle
class VoiceIdle extends VoiceState {
  const VoiceIdle();
}

/// Voice recognition is initializing
class VoiceInitializing extends VoiceState {
  const VoiceInitializing();
}

/// Voice recognition is ready
class VoiceReady extends VoiceState {
  const VoiceReady();
}

/// Voice recognition is listening
class VoiceListening extends VoiceState {
  const VoiceListening();
}

/// Text recognized from voice
class VoiceRecognized extends VoiceState {
  const VoiceRecognized(this.text);
  
  final String text;
}

/// Voice recognition error occurred
class VoiceError extends VoiceState {
  const VoiceError(this.message);
  
  final String message;
}
