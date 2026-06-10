import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

class AudioStreamService {
  static const double _dbMin = -2.0;
  static const double _dbMax = 10.0;
  static const double _noiseFloor = 0.03;
  static const double _attackSmoothing = 0.45;
  static const double _releaseSmoothing = 0.15;

  AudioStreamService({AudioRecorder? audioRecorder})
      : _audioRecorder = audioRecorder ?? AudioRecorder();

  final AudioRecorder _audioRecorder;
  final StreamController<double> _audioLevelController =
      StreamController<double>.broadcast();
  StreamSubscription<Uint8List>? _audioSubscription;
  bool _isRunning = false;
  double _audioLevel = 0.0;

  final List<void Function(Uint8List)> _dataCallbacks = [];
  void Function(Object error, StackTrace stackTrace)? _errorCallback;

  bool get isRunning => _isRunning;
  double get audioLevel => _audioLevel;
  Stream<double> get audioLevelStream => _audioLevelController.stream;

  void addDataCallback(void Function(Uint8List) callback) {
    _dataCallbacks.add(callback);
  }

  void removeDataCallback(void Function(Uint8List) callback) {
    _dataCallbacks.remove(callback);
  }

  Future<bool> requestPermission() {
    return _audioRecorder.hasPermission();
  }

  Future<void> start({
    void Function(Uint8List bytes)? onData,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    if (_isRunning) {
      if (onData != null) {
        addDataCallback(onData);
      }
      if (onError != null) {
        _errorCallback = onError;
      }
      return;
    }

    final audioStream = await _audioRecorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    if (onData != null) {
      addDataCallback(onData);
    }
    if (onError != null) {
      _errorCallback = onError;
    }

    _audioSubscription = audioStream.listen(
      (Uint8List bytes) {
        // _publishAudioLevel(bytes);
        for (final cb in _dataCallbacks) {
          cb(bytes);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _errorCallback?.call(error, stackTrace);
      },
    );

    _isRunning = true;
  }

  Future<void> stop() async {
    await _audioSubscription?.cancel();
    _audioSubscription = null;

    if (await _audioRecorder.isRecording()) {
      await _audioRecorder.stop();
    }

    _dataCallbacks.clear();
    _errorCallback = null;
    _isRunning = false;
    _setAudioLevel(0.0);
  }

  Future<void> pauseCallbacks() async {
    _dataCallbacks.clear();
    _errorCallback = null;
  }

  Future<void> dispose() async {
    await stop();
    await _audioLevelController.close();
    await _audioRecorder.dispose();
  }

  void _publishAudioLevel(Uint8List bytes) {
    if (bytes.lengthInBytes < 2) {
      _setAudioLevel(0.0);
      return;
    }

    final sampleCount = bytes.lengthInBytes ~/ 2;
    final byteData = ByteData.sublistView(bytes, 0, sampleCount * 2);

    var sumSquares = 0.0;
    for (var i = 0; i < sampleCount; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little) / 32768.0;
      sumSquares += sample * sample;
    }

    final rms = math.sqrt(sumSquares / sampleCount);
    final normalized = _normalizeRms(rms);
    final smoothed = _smoothAudioLevel(normalized);

    // print(
    //   '[NORMALIZED AUDIO LEVEL]: $smoothed',
    // );
    _setAudioLevel(smoothed);
  }

  double _normalizeRms(double rms) {
    final boosted = math.sqrt(rms.clamp(0.0, 1.0).toDouble());
    if (boosted <= _noiseFloor) {
      return 0.0;
    }

    return ((boosted - _noiseFloor) / (1.0 - _noiseFloor))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double _smoothAudioLevel(double target) {
    final smoothing =
        target > _audioLevel ? _attackSmoothing : _releaseSmoothing;
    return _audioLevel + (target - _audioLevel) * smoothing;
  }

  void _setAudioLevel(double value) {
    _audioLevel = value;
    if (!_audioLevelController.isClosed) {
      _audioLevelController.add(value);
    }
  }
}
