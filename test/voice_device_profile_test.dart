import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_device_profile.dart';

void main() {
  test('unknown profile uses the safe default source', () {
    final VoiceDeviceProfile profile =
        VoiceDeviceProfile.resolve(profileId: 'unknown-device');

    expect(profile.id, 'default');
    expect(profile.androidAudioSource, AndroidAudioSource.voiceCommunication);
    expect(profile.forceHardRestartOnResume, isFalse);
  });

  test('T2151 profile enables the interruption recovery policy', () {
    final VoiceDeviceProfile profile =
        VoiceDeviceProfile.resolve(profileId: 't2151');

    expect(profile.id, 't2151');
    expect(profile.forceHardRestartOnResume, isTrue);
    expect(profile.forceHardRestartAfterUnsilence, isTrue);
    expect(profile.forceHardRestartOnAudioRouteChange, isTrue);
    expect(profile.manageBluetooth, isFalse);
    expect(profile.selectUsbInputExplicitly, isTrue);
    expect(profile.captureStartupWav, isTrue);
    expect(profile.vadSpeechOnRms, 0.0005);
    expect(profile.vadSpeechOffRms, 0.0003);
  });

  test('T2151 A/B profiles select the requested Android source', () {
    final VoiceDeviceProfile recognition =
        VoiceDeviceProfile.resolve(profileId: 't2151_voice_recognition');
    expect(
      recognition.androidAudioSource,
      AndroidAudioSource.voiceRecognition,
    );
    expect(recognition.requireNonZeroPcmForStartup, isTrue);
    expect(
        recognition.exactZeroStartupGrace, const Duration(milliseconds: 1200));
    expect(
        recognition.recoveryCaptureTimeout, const Duration(milliseconds: 2500));
    expect(recognition.maxStartupRecorderRecreates, 1);
    expect(recognition.fallbackToVoiceCommunication, isTrue);
    expect(recognition.captureStartupWav, isTrue);
    expect(
      VoiceDeviceProfile.resolve(profileId: 't2151_microphone')
          .androidAudioSource,
      AndroidAudioSource.mic,
    );
  });
}
