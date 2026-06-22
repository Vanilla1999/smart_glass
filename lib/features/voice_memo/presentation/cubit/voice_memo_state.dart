sealed class VoiceMemoState {
  const VoiceMemoState();
}

class VoiceMemoIdle extends VoiceMemoState {
  const VoiceMemoIdle();
}

class VoiceMemoRecording extends VoiceMemoState {
  const VoiceMemoRecording();
}

class VoiceMemoSaved extends VoiceMemoState {
  const VoiceMemoSaved({required this.filePath});

  final String filePath;
}

class VoiceMemoError extends VoiceMemoState {
  const VoiceMemoError({required this.message});

  final String message;
}
