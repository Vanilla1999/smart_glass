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
  });

  test('T2151 A/B profiles select the requested Android source', () {
    expect(
      VoiceDeviceProfile.resolve(profileId: 't2151_voice_recognition')
          .androidAudioSource,
      AndroidAudioSource.voiceRecognition,
    );
    expect(
      VoiceDeviceProfile.resolve(profileId: 't2151_microphone')
          .androidAudioSource,
      AndroidAudioSource.mic,
    );
  });
}
