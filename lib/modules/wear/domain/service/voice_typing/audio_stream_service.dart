import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

class AudioStreamService {
  static const double _liveGainMultiplier = 3.0;
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
  int _chunksReceived = 0;
  int? _lastChunkAtMillis;
  int? _lastNonSilentChunkAtMillis;
  int? _continuousZeroAudioStartedAtMillis;
  int? _startedAtMillis;

  final List<void Function(Uint8List)> _dataCallbacks = [];
  void Function(Object error, StackTrace stackTrace)? _errorCallback;

  bool get isRunning => _isRunning;
  double get audioLevel => _audioLevel;
  int get chunksReceived => _chunksReceived;
  int? get lastChunkAtMillis => _lastChunkAtMillis;
  int? get lastNonSilentChunkAtMillis => _lastNonSilentChunkAtMillis;
  int? get continuousZeroAudioStartedAtMillis =>
      _continuousZeroAudioStartedAtMillis;
  Stream<double> get audioLevelStream => _audioLevelController.stream;

  void addDataCallback(void Function(Uint8List) callback) {
    if (!_dataCallbacks.contains(callback)) {
      _dataCallbacks.add(callback);
    }
  }

  void removeDataCallback(void Function(Uint8List) callback) {
    _dataCallbacks.remove(callback);
  }

  Future<bool> requestPermission() {
    return _audioRecorder.hasPermission();
  }

  Future<String> diagnostics() async {
    final bool isRecording = await _audioRecorder.isRecording();
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int? lastChunkAgeMs =
        _lastChunkAtMillis == null ? null : now - _lastChunkAtMillis!;
    final int? lastNonSilentAgeMs = _lastNonSilentChunkAtMillis == null
        ? null
        : now - _lastNonSilentChunkAtMillis!;
    final int? continuousZeroAudioAgeMs =
        _continuousZeroAudioStartedAtMillis == null
            ? null
            : now - _continuousZeroAudioStartedAtMillis!;
    final int? runningForMs =
        _startedAtMillis == null ? null : now - _startedAtMillis!;
    return 'AudioStreamService{isRunning=$_isRunning, '
        'recorderIsRecording=$isRecording, callbacks=${_dataCallbacks.length}, '
        'chunks=$_chunksReceived, lastChunkAgeMs=$lastChunkAgeMs, '
        'lastNonSilentAgeMs=$lastNonSilentAgeMs, '
        'continuousZeroAudioAgeMs=$continuousZeroAudioAgeMs, '
        'runningForMs=$runningForMs}';
  }

  Future<void> start({
    void Function(Uint8List bytes)? onData,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    if (_isRunning) {
      print(
        '[AudioStreamService] start called while running; '
        'callbacks=${_dataCallbacks.length}',
      );
      if (onData != null) {
        addDataCallback(onData);
      }
      if (onError != null) {
        _errorCallback = onError;
      }
      return;
    }

    _chunksReceived = 0;
    _lastChunkAtMillis = null;
    _continuousZeroAudioStartedAtMillis = null;
    _startedAtMillis = DateTime.now().millisecondsSinceEpoch;
    _lastNonSilentChunkAtMillis = null;
    print('[AudioStreamService] startStream begin at $_startedAtMillis');

    final audioStream = await _audioRecorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        androidConfig: AndroidRecordConfig(
          audioSource: AndroidAudioSource.voiceRecognition,
          service: AndroidService(
            title: 'Smart Glasses',
            content: 'Голосовое управление активно',
          ),
        ),
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
        final boostedBytes = _boostPcm16(bytes);
        _chunksReceived++;
        _lastChunkAtMillis = DateTime.now().millisecondsSinceEpoch;
        final _PcmStats stats = _pcmStats(boostedBytes);
        if (stats.peak > 0.0001) {
          _lastNonSilentChunkAtMillis = _lastChunkAtMillis;
        }
        if (stats.peak == 0.0) {
          _continuousZeroAudioStartedAtMillis ??= _lastChunkAtMillis;
        } else {
          _continuousZeroAudioStartedAtMillis = null;
        }
        if (_chunksReceived == 1 || _chunksReceived % 200 == 0) {
          print(
            '[AudioStreamService] chunk#$_chunksReceived '
            'bytes=${boostedBytes.lengthInBytes} callbacks=${_dataCallbacks.length} '
            'rms=${stats.rms.toStringAsFixed(5)} '
            'peak=${stats.peak.toStringAsFixed(5)} '
            'at=$_lastChunkAtMillis',
          );
        }
        // _publishAudioLevel(boostedBytes);
        for (final cb in List<void Function(Uint8List)>.of(_dataCallbacks)) {
          cb(boostedBytes);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _isRunning = false;
        print('[AudioStreamService] stream error: $error\n$stackTrace');
        _errorCallback?.call(error, stackTrace);
      },
      onDone: () {
        _isRunning = false;
        print('[AudioStreamService] audio stream done');
      },
    );

    _isRunning = true;
    print('[AudioStreamService] startStream done');
  }

  Future<void> stop() async {
    print('[AudioStreamService] stop begin: ${await diagnostics()}');
    await _audioSubscription?.cancel();
    _audioSubscription = null;

    if (await _audioRecorder.isRecording()) {
      await _audioRecorder.stop();
    }

    _dataCallbacks.clear();
    _errorCallback = null;
    _isRunning = false;
    _startedAtMillis = null;
    _continuousZeroAudioStartedAtMillis = null;
    _setAudioLevel(0.0);
    print('[AudioStreamService] stop done');
  }

  Future<void> pauseCallbacks() async {
    print(
        '[AudioStreamService] pauseCallbacks callbacks=${_dataCallbacks.length}');
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

  Uint8List _boostPcm16(Uint8List bytes) {
    if (bytes.lengthInBytes < 2) {
      return bytes;
    }

    final boosted = Uint8List.fromList(bytes);
    final sampleCount = boosted.lengthInBytes ~/ 2;
    final byteData = ByteData.sublistView(boosted, 0, sampleCount * 2);

    for (var i = 0; i < sampleCount; i++) {
      final offset = i * 2;
      final sample = byteData.getInt16(offset, Endian.little);
      final amplified =
          (sample * _liveGainMultiplier).round().clamp(-32768, 32767);
      byteData.setInt16(offset, amplified, Endian.little);
    }

    return boosted;
  }

  _PcmStats _pcmStats(Uint8List bytes) {
    if (bytes.lengthInBytes < 2) {
      return const _PcmStats(rms: 0, peak: 0);
    }

    final sampleCount = bytes.lengthInBytes ~/ 2;
    final byteData = ByteData.sublistView(bytes, 0, sampleCount * 2);
    var sumSquares = 0.0;
    var peak = 0.0;
    for (var i = 0; i < sampleCount; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little) / 32768.0;
      final abs = sample.abs();
      if (abs > peak) peak = abs;
      sumSquares += sample * sample;
    }

    return _PcmStats(
      rms: math.sqrt(sumSquares / sampleCount),
      peak: peak,
    );
  }
}

class _PcmStats {
  const _PcmStats({required this.rms, required this.peak});

  final double rms;
  final double peak;
}
