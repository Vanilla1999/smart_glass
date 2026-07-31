import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/core/voice/native_voice_capture.dart';

void main() {
  test('all planned native lifecycle states decode exhaustively', () {
    const Map<String, NativeVoiceCaptureState> states =
        <String, NativeVoiceCaptureState>{
      'checkingCapabilities': NativeVoiceCaptureState.checkingCapabilities,
      'unsupportedFirmware': NativeVoiceCaptureState.unsupportedFirmware,
      'activating': NativeVoiceCaptureState.activating,
      'activated': NativeVoiceCaptureState.activated,
      'binding': NativeVoiceCaptureState.binding,
      'bound': NativeVoiceCaptureState.bound,
      'initializing': NativeVoiceCaptureState.initializing,
      'initialized': NativeVoiceCaptureState.initialized,
      'starting': NativeVoiceCaptureState.starting,
      'streaming': NativeVoiceCaptureState.streaming,
      'stopping': NativeVoiceCaptureState.stopping,
      'deinitializing': NativeVoiceCaptureState.deinitializing,
      'unbinding': NativeVoiceCaptureState.unbinding,
      'idle': NativeVoiceCaptureState.idle,
      'error': NativeVoiceCaptureState.error,
      'terminalAbandoned': NativeVoiceCaptureState.terminalAbandoned,
      'disposed': NativeVoiceCaptureState.disposed,
    };

    for (final MapEntry<String, NativeVoiceCaptureState> entry
        in states.entries) {
      expect(
        NativeVoiceCapture.decodeStateEvent(<Object?, Object?>{
          'state': entry.key,
        }).state,
        entry.value,
      );
    }
  });

  test('sspInitialized is successful initialized compatibility state', () {
    expect(
      NativeVoiceCapture.decodeStateEvent(<Object?, Object?>{
        'state': 'sspInitialized',
      }).state,
      NativeVoiceCaptureState.initialized,
    );
  });

  test('unknown native state fails closed without masquerading as error', () {
    expect(
      NativeVoiceCapture.decodeStateEvent(<Object?, Object?>{
        'state': 'futureState',
      }).state,
      NativeVoiceCaptureState.unknown,
    );
  });

  test('native termination details survive event decoding', () {
    final NativeVoiceStateEvent event =
        NativeVoiceCapture.decodeStateEvent(<Object?, Object?>{
      'state': 'error',
      'errorCode': 'PCM_QUEUE_OVERRUN',
      'errorDetails': 'stage=callback_budget callbackBytes=262144',
    });

    expect(event.errorCode, 'PCM_QUEUE_OVERRUN');
    expect(
      event.errorDetails,
      'stage=callback_budget callbackBytes=262144',
    );
  });
}
