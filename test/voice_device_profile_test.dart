import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_device_profile.dart';

void main() {
  test('all launches use the single UAC4 capture policy', () {
    final VoiceDeviceProfile profile =
        VoiceDeviceProfile.resolve(profileId: 'obsolete_audio_record_profile');

    expect(profile.id, 'uac4');
    expect(profile.forceHardRestartOnResume, isTrue);
    expect(profile.requireNonZeroPcmForStartup, isTrue);
    expect(profile.exactZeroStartupGrace, const Duration(seconds: 15));
    expect(profile.recoveryCaptureTimeout, const Duration(seconds: 15));
    expect(profile.maxStartupRecorderRecreates, 0);
  });
}
