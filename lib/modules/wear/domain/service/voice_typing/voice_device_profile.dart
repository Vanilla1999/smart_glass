import 'package:record/record.dart';

const bool voiceCaptureWavDiagnostics = bool.fromEnvironment(
  'VOICE_CAPTURE_WAV_DIAGNOSTICS',
  defaultValue: false,
);

enum VoiceAudioSource {
  voiceCommunication,
  voiceRecognition,
  microphone,
}

class VoiceDeviceProfile {
  const VoiceDeviceProfile({
    required this.id,
    required this.audioSource,
    required this.forceHardRestartOnResume,
    required this.forceHardRestartAfterUnsilence,
    required this.forceHardRestartOnAudioRouteChange,
    required this.manageBluetooth,
    required this.speakerphone,
    required this.audioManagerMode,
    required this.requireNonZeroPcmForStartup,
    required this.exactZeroStartupGrace,
    required this.recoveryCaptureTimeout,
    required this.postRecreateExactZeroStartupGrace,
    required this.postRecreateCaptureTimeout,
    required this.maxStartupRecorderRecreates,
    required this.fallbackToVoiceCommunication,
    required this.selectUsbInputExplicitly,
    required this.requireExpectedInputDevice,
    required this.captureStartupWav,
    required this.vadSpeechOnRms,
    required this.vadSpeechOffRms,
  });

  static const VoiceDeviceProfile defaultProfile = VoiceDeviceProfile(
    id: 'default',
    audioSource: VoiceAudioSource.voiceCommunication,
    forceHardRestartOnResume: false,
    forceHardRestartAfterUnsilence: true,
    forceHardRestartOnAudioRouteChange: false,
    manageBluetooth: true,
    speakerphone: false,
    audioManagerMode: AudioManagerMode.modeNormal,
    requireNonZeroPcmForStartup: false,
    exactZeroStartupGrace: Duration.zero,
    recoveryCaptureTimeout: Duration(seconds: 2),
    postRecreateExactZeroStartupGrace: Duration.zero,
    postRecreateCaptureTimeout: Duration(seconds: 2),
    maxStartupRecorderRecreates: 0,
    fallbackToVoiceCommunication: false,
    selectUsbInputExplicitly: false,
    requireExpectedInputDevice: false,
    captureStartupWav: false,
    vadSpeechOnRms: 0.0010,
    vadSpeechOffRms: 0.0007,
  );

  static const VoiceDeviceProfile t2151 = VoiceDeviceProfile(
    id: 't2151',
    audioSource: VoiceAudioSource.voiceCommunication,
    forceHardRestartOnResume: true,
    forceHardRestartAfterUnsilence: true,
    forceHardRestartOnAudioRouteChange: true,
    manageBluetooth: false,
    speakerphone: false,
    audioManagerMode: AudioManagerMode.modeNormal,
    requireNonZeroPcmForStartup: false,
    exactZeroStartupGrace: Duration.zero,
    recoveryCaptureTimeout: Duration(seconds: 2),
    postRecreateExactZeroStartupGrace: Duration.zero,
    postRecreateCaptureTimeout: Duration(seconds: 2),
    maxStartupRecorderRecreates: 0,
    fallbackToVoiceCommunication: false,
    selectUsbInputExplicitly: true,
    requireExpectedInputDevice: true,
    captureStartupWav: voiceCaptureWavDiagnostics,
    vadSpeechOnRms: 0.0005,
    vadSpeechOffRms: 0.0003,
  );

  static const VoiceDeviceProfile t2151VoiceRecognition = VoiceDeviceProfile(
    id: 't2151_voice_recognition',
    audioSource: VoiceAudioSource.voiceRecognition,
    forceHardRestartOnResume: true,
    forceHardRestartAfterUnsilence: true,
    forceHardRestartOnAudioRouteChange: true,
    manageBluetooth: false,
    speakerphone: false,
    audioManagerMode: AudioManagerMode.modeNormal,
    requireNonZeroPcmForStartup: true,
    exactZeroStartupGrace: Duration(seconds: 15),
    recoveryCaptureTimeout: Duration(seconds: 15),
    postRecreateExactZeroStartupGrace: Duration(milliseconds: 3000),
    postRecreateCaptureTimeout: Duration(milliseconds: 4000),
    maxStartupRecorderRecreates: 0,
    fallbackToVoiceCommunication: false,
    selectUsbInputExplicitly: true,
    requireExpectedInputDevice: true,
    captureStartupWav: voiceCaptureWavDiagnostics,
    vadSpeechOnRms: 0.0008,
    vadSpeechOffRms: 0.0005,
  );

  static const VoiceDeviceProfile t2151Microphone = VoiceDeviceProfile(
    id: 't2151_microphone',
    audioSource: VoiceAudioSource.microphone,
    forceHardRestartOnResume: true,
    forceHardRestartAfterUnsilence: true,
    forceHardRestartOnAudioRouteChange: true,
    manageBluetooth: false,
    speakerphone: false,
    audioManagerMode: AudioManagerMode.modeNormal,
    requireNonZeroPcmForStartup: false,
    exactZeroStartupGrace: Duration.zero,
    recoveryCaptureTimeout: Duration(seconds: 2),
    postRecreateExactZeroStartupGrace: Duration.zero,
    postRecreateCaptureTimeout: Duration(seconds: 2),
    maxStartupRecorderRecreates: 0,
    fallbackToVoiceCommunication: false,
    selectUsbInputExplicitly: false,
    requireExpectedInputDevice: false,
    captureStartupWav: false,
    vadSpeechOnRms: 0.0008,
    vadSpeechOffRms: 0.0005,
  );

  final String id;
  final VoiceAudioSource audioSource;
  final bool forceHardRestartOnResume;
  final bool forceHardRestartAfterUnsilence;

  /// Only native audio-route events may use this policy; UI routes never do.
  final bool forceHardRestartOnAudioRouteChange;
  final bool manageBluetooth;
  final bool speakerphone;
  final AudioManagerMode audioManagerMode;
  final bool requireNonZeroPcmForStartup;
  final Duration exactZeroStartupGrace;
  final Duration recoveryCaptureTimeout;
  final Duration postRecreateExactZeroStartupGrace;
  final Duration postRecreateCaptureTimeout;
  final int maxStartupRecorderRecreates;
  final bool fallbackToVoiceCommunication;
  final bool selectUsbInputExplicitly;
  final bool requireExpectedInputDevice;
  final bool captureStartupWav;

  /// Raw PCM VAD thresholds. They are deliberately independent of recognizer gain.
  final double vadSpeechOnRms;
  final double vadSpeechOffRms;

  AndroidAudioSource get androidAudioSource => switch (audioSource) {
        VoiceAudioSource.voiceCommunication =>
          AndroidAudioSource.voiceCommunication,
        VoiceAudioSource.voiceRecognition =>
          AndroidAudioSource.voiceRecognition,
        VoiceAudioSource.microphone => AndroidAudioSource.mic,
      };

  static VoiceDeviceProfile resolve({String? profileId}) {
    final String value = (profileId ??
            const String.fromEnvironment(
              'VOICE_DEVICE_PROFILE',
              defaultValue: 'default',
            ))
        .toLowerCase();
    return switch (value) {
      't2151' => t2151,
      't2151_voice_recognition' => t2151VoiceRecognition,
      't2151_microphone' => t2151Microphone,
      _ => defaultProfile,
    };
  }
}
