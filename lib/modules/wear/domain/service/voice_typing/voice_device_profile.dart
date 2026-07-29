const bool voiceCaptureWavDiagnostics = bool.fromEnvironment(
  'VOICE_CAPTURE_WAV_DIAGNOSTICS',
  defaultValue: false,
);

class VoiceDeviceProfile {
  const VoiceDeviceProfile({
    required this.id,
    required this.forceHardRestartOnResume,
    required this.forceHardRestartAfterUnsilence,
    required this.requireNonZeroPcmForStartup,
    required this.exactZeroStartupGrace,
    required this.recoveryCaptureTimeout,
    required this.postRecreateExactZeroStartupGrace,
    required this.postRecreateCaptureTimeout,
    required this.maxStartupRecorderRecreates,
    required this.captureStartupWav,
    required this.vadSpeechOnRms,
    required this.vadSpeechOffRms,
  });

  static const VoiceDeviceProfile defaultProfile = VoiceDeviceProfile(
    id: 'uac4',
    forceHardRestartOnResume: true,
    forceHardRestartAfterUnsilence: true,
    requireNonZeroPcmForStartup: true,
    exactZeroStartupGrace: Duration(seconds: 15),
    recoveryCaptureTimeout: Duration(seconds: 15),
    postRecreateExactZeroStartupGrace: Duration(seconds: 15),
    postRecreateCaptureTimeout: Duration(seconds: 15),
    maxStartupRecorderRecreates: 0,
    captureStartupWav: voiceCaptureWavDiagnostics,
    vadSpeechOnRms: 0.0025,
    vadSpeechOffRms: 0.0013,
  );

  final String id;
  final bool forceHardRestartOnResume;
  final bool forceHardRestartAfterUnsilence;
  final bool requireNonZeroPcmForStartup;
  final Duration exactZeroStartupGrace;
  final Duration recoveryCaptureTimeout;
  final Duration postRecreateExactZeroStartupGrace;
  final Duration postRecreateCaptureTimeout;
  final int maxStartupRecorderRecreates;
  final bool captureStartupWav;
  final double vadSpeechOnRms;
  final double vadSpeechOffRms;

  static VoiceDeviceProfile resolve({String? profileId}) => defaultProfile;
}
