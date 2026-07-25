import 'package:record/record.dart';

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
