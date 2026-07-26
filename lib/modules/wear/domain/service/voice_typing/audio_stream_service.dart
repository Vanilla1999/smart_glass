import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_device_profile.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_startup_wav_capture.dart';

class VoiceRecorderLifecycle {
  static Future<void> recreate({
    required Future<void> Function() stop,
    required Future<void> Function() dispose,
    required void Function() create,
  }) async {
    await stop();
    await dispose();
    create();
  }
}

class AudioStreamService {
  static const double _liveGainMultiplier = 3.0;
  static const double _dbMin = -2.0;
  static const double _dbMax = 10.0;
  static const double _noiseFloor = 0.03;
  static const double _attackSmoothing = 0.45;
  static const double _releaseSmoothing = 0.15;
  static const int _startupDiagnosticsDurationMs = 10000;
  static const int _startupDiagnosticsIntervalMs = 500;
  static const Duration _startupWavDuration = Duration(seconds: 8);

  AudioStreamService({
    AudioRecorder? audioRecorder,
    AudioRecorder Function()? audioRecorderFactory,
    VoiceDeviceProfile? deviceProfile,
  })  : _audioRecorderFactory = audioRecorderFactory ?? AudioRecorder.new,
        _deviceProfile = deviceProfile ?? VoiceDeviceProfile.resolve(),
        _audioRecorder =
            audioRecorder ?? (audioRecorderFactory ?? AudioRecorder.new)();

  final AudioRecorder Function() _audioRecorderFactory;
  VoiceDeviceProfile _deviceProfile;
  AudioRecorder _audioRecorder;
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
  int? _startupDiagnosticsStartedAtMillis;
  int? _startupDiagnosticsNextAtMillis;
  int _startupDiagnosticsChunks = 0;
  double _startupDiagnosticsMaxRms = 0.0;
  double _startupDiagnosticsMaxPeak = 0.0;
  int _captureId = 0;
  InputDevice? _preferredInputDevice;
  VoiceStartupWavCapture? _startupWavCapture;
  String? _startupWavPath;
  bool _startupWavSaved = false;

  final List<void Function(Uint8List)> _dataCallbacks = [];
  final List<void Function(Uint8List raw, Uint8List boosted)> _pcmCallbacks =
      [];
  void Function(Object error, StackTrace stackTrace)? _errorCallback;

  bool get isRunning => _isRunning;
  double get audioLevel => _audioLevel;
  int get chunksReceived => _chunksReceived;
  int? get lastChunkAtMillis => _lastChunkAtMillis;
  int? get lastNonSilentChunkAtMillis => _lastNonSilentChunkAtMillis;
  int? get continuousZeroAudioStartedAtMillis =>
      _continuousZeroAudioStartedAtMillis;
  int? get captureStartedAtMillis => _startedAtMillis;
  int get captureId => _captureId;
  VoiceDeviceProfile get deviceProfile => _deviceProfile;
  Stream<double> get audioLevelStream => _audioLevelController.stream;

  void addDataCallback(void Function(Uint8List) callback) {
    if (!_dataCallbacks.contains(callback)) {
      _dataCallbacks.add(callback);
    }
  }

  void removeDataCallback(void Function(Uint8List) callback) {
    _dataCallbacks.remove(callback);
  }

  void addPcmCallback(
      void Function(Uint8List raw, Uint8List boosted) callback) {
    if (!_pcmCallbacks.contains(callback)) _pcmCallbacks.add(callback);
  }

  void removePcmCallback(
    void Function(Uint8List raw, Uint8List boosted) callback,
  ) {
    _pcmCallbacks.remove(callback);
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
    return 'AudioStreamService{captureId=$_captureId, isRunning=$_isRunning, '
        'recorderIsRecording=$isRecording, '
        'dataCallbacks=${_dataCallbacks.length}, '
        'pcmCallbacks=${_pcmCallbacks.length}, '
        'chunks=$_chunksReceived, lastChunkAgeMs=$lastChunkAgeMs, '
        'lastNonSilentAgeMs=$lastNonSilentAgeMs, '
        'continuousZeroAudioAgeMs=$continuousZeroAudioAgeMs, '
        'preferredInputDevice=${_preferredInputDevice?.label} '
        'preferredInputDeviceId=${_preferredInputDevice?.id}, '
        'startupWavPath=$_startupWavPath '
        'startupWavBytes=${_startupWavCapture?.pcmBytes}, '
        'runningForMs=$runningForMs}';
  }

  Future<void> start({
    void Function(Uint8List bytes)? onData,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    if (_isRunning) {
      print(
        '[AudioStreamService] start called while running; '
        'dataCallbacks=${_dataCallbacks.length} '
        'pcmCallbacks=${_pcmCallbacks.length}',
      );
      if (onData != null) {
        addDataCallback(onData);
      }
      if (onError != null) {
        _errorCallback = onError;
      }
      return;
    }

    _captureId++;
    _chunksReceived = 0;
    _lastChunkAtMillis = null;
    _continuousZeroAudioStartedAtMillis = null;
    _startedAtMillis = DateTime.now().millisecondsSinceEpoch;
    _lastNonSilentChunkAtMillis = null;
    _beginStartupDiagnostics();
    await _beginStartupWavCapture();
    print(
      '[VoiceCapture#$_captureId] start at $_startedAtMillis '
      'profile=${_deviceProfile.id} source=${_deviceProfile.audioSource.name}',
    );
    _preferredInputDevice = await _selectPreferredInputDevice();

    final audioStream = await _audioRecorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        device: _preferredInputDevice,
        androidConfig: AndroidRecordConfig(
          audioSource: _deviceProfile.androidAudioSource,
          manageBluetooth: _deviceProfile.manageBluetooth,
          speakerphone: _deviceProfile.speakerphone,
          audioManagerMode: _deviceProfile.audioManagerMode,
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
        if (bytes.lengthInBytes < 2) {
          print('[VoiceCapture#$_captureId] ignored empty PCM stream event');
          return;
        }
        final _PcmStats rawStats = _pcmStats(bytes);
        _captureStartupWav(bytes);
        final boostedBytes = _boostPcm16(bytes);
        _chunksReceived++;
        _lastChunkAtMillis = DateTime.now().millisecondsSinceEpoch;
        final _PcmStats stats = _pcmStats(boostedBytes);
        if (rawStats.peak > 0.0) {
          _lastNonSilentChunkAtMillis = _lastChunkAtMillis;
        }
        if (rawStats.peak == 0.0) {
          _continuousZeroAudioStartedAtMillis ??= _lastChunkAtMillis;
        } else {
          _continuousZeroAudioStartedAtMillis = null;
        }
        _logStartupDiagnostics(rawStats, stats);
        if (_chunksReceived == 1 || _chunksReceived % 200 == 0) {
          print(
            '[VoiceCapture#$_captureId] chunk#$_chunksReceived '
            'bytes=${boostedBytes.lengthInBytes} '
            'dataCallbacks=${_dataCallbacks.length} '
            'pcmCallbacks=${_pcmCallbacks.length} '
            'rawRms=${rawStats.rms.toStringAsFixed(5)} '
            'rawPeak=${rawStats.peak.toStringAsFixed(5)} '
            'postGainRms=${stats.rms.toStringAsFixed(5)} '
            'postGainPeak=${stats.peak.toStringAsFixed(5)} '
            'at=$_lastChunkAtMillis',
          );
        }
        // _publishAudioLevel(boostedBytes);
        for (final cb in List<void Function(Uint8List)>.of(_dataCallbacks)) {
          cb(boostedBytes);
        }
        for (final cb
            in List<void Function(Uint8List raw, Uint8List boosted)>.of(
          _pcmCallbacks,
        )) {
          cb(bytes, boostedBytes);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _isRunning = false;
        print('[AudioStreamService] stream error: $error\n$stackTrace');
        _errorCallback?.call(error, stackTrace);
      },
      onDone: () {
        _isRunning = false;
        final StateError error = StateError('Audio stream ended unexpectedly');
        print('[VoiceCapture#$_captureId] audio stream done');
        _errorCallback?.call(error, StackTrace.current);
      },
    );

    _isRunning = true;
    print('[VoiceCapture#$_captureId] start done');
  }

  Future<void> stop() async {
    print('[VoiceCapture#$_captureId] stop begin: ${await diagnostics()}');
    await _audioSubscription?.cancel();
    _audioSubscription = null;

    if (await _audioRecorder.isRecording()) {
      await _audioRecorder.stop();
    }

    _dataCallbacks.clear();
    _pcmCallbacks.clear();
    _errorCallback = null;
    _isRunning = false;
    _startedAtMillis = null;
    _continuousZeroAudioStartedAtMillis = null;
    _setAudioLevel(0.0);
    print('[VoiceCapture#$_captureId] stop done');
  }

  Future<void> recreateRecorder() async {
    await VoiceRecorderLifecycle.recreate(
      stop: stop,
      dispose: _audioRecorder.dispose,
      create: () => _audioRecorder = _audioRecorderFactory(),
    );
    print('[VoiceCapture#$_captureId] recorder released and recreated');
  }

  Future<InputDevice?> _selectPreferredInputDevice() async {
    if (!_deviceProfile.selectUsbInputExplicitly) return null;
    final List<InputDevice> devices = await _audioRecorder.listInputDevices();
    InputDevice? selected;
    for (final InputDevice device in devices) {
      final String label = device.label.toLowerCase();
      if (label.contains('usb') ||
          label.contains('uvc') ||
          label.contains('rockchip')) {
        selected = device;
        break;
      }
    }
    print(
      '[VoiceCapture#$_captureId] input devices=$devices '
      'preferred=${selected?.label} id=${selected?.id}',
    );
    return selected;
  }

  Future<void> _beginStartupWavCapture() async {
    _startupWavCapture = null;
    _startupWavPath = null;
    _startupWavSaved = false;
    if (!_deviceProfile.captureStartupWav) return;

    try {
      final Directory directory = await getTemporaryDirectory();
      final Directory captureDirectory =
          Directory('${directory.path}/voice_capture');
      await captureDirectory.create(recursive: true);
      _startupWavCapture =
          VoiceStartupWavCapture(duration: _startupWavDuration);
      _startupWavPath = '${captureDirectory.path}/'
          'capture_${_captureId}_${_startedAtMillis}_${_deviceProfile.id}.wav';
      print(
          '[VoiceCapture#$_captureId] startup WAV armed path=$_startupWavPath');
    } catch (error, stackTrace) {
      print(
          '[VoiceCapture#$_captureId] startup WAV disabled: $error\n$stackTrace');
    }
  }

  void _captureStartupWav(Uint8List rawBytes) {
    final VoiceStartupWavCapture? capture = _startupWavCapture;
    final String? path = _startupWavPath;
    if (capture == null || path == null || _startupWavSaved) return;

    capture.add(rawBytes);
    if (!capture.hasReachedLimit) return;
    _startupWavSaved = true;
    unawaited(File(path).writeAsBytes(capture.toWavBytes(), flush: true).then(
          (_) => print(
            '[VoiceCapture#$_captureId] startup WAV saved '
            'path=$path pcmBytes=${capture.pcmBytes}',
          ),
          onError: (Object error, StackTrace stackTrace) => print(
            '[VoiceCapture#$_captureId] startup WAV save failed: '
            '$error\n$stackTrace',
          ),
        ));
  }

  void useDeviceProfile(VoiceDeviceProfile profile) {
    if (_isRunning) {
      throw StateError(
          'Cannot change the audio profile while capture is active.');
    }
    _deviceProfile = profile;
    print('[AudioStreamService] active profile=${profile.id}');
  }

  Future<void> pauseCallbacks() async {
    print('[AudioStreamService] pauseCallbacks '
        'dataCallbacks=${_dataCallbacks.length} '
        'pcmCallbacks=${_pcmCallbacks.length}');
    _dataCallbacks.clear();
    _pcmCallbacks.clear();
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

  void _beginStartupDiagnostics() {
    _startupDiagnosticsStartedAtMillis = _startedAtMillis;
    _startupDiagnosticsNextAtMillis =
        (_startedAtMillis ?? 0) + _startupDiagnosticsIntervalMs;
    _startupDiagnosticsChunks = 0;
    _startupDiagnosticsMaxRms = 0.0;
    _startupDiagnosticsMaxPeak = 0.0;
    print(
      '[AudioStreamService] startup audio diagnostics armed '
      'durationMs=$_startupDiagnosticsDurationMs '
      'intervalMs=$_startupDiagnosticsIntervalMs',
    );
  }

  void _logStartupDiagnostics(_PcmStats rawStats, _PcmStats postGainStats) {
    final int? startedAt = _startupDiagnosticsStartedAtMillis;
    final int? now = _lastChunkAtMillis;
    if (startedAt == null || now == null) return;
    final int offsetMs = now - startedAt;
    if (offsetMs > _startupDiagnosticsDurationMs) {
      _startupDiagnosticsStartedAtMillis = null;
      return;
    }

    _startupDiagnosticsChunks++;
    _startupDiagnosticsMaxRms =
        math.max(_startupDiagnosticsMaxRms, rawStats.rms);
    _startupDiagnosticsMaxPeak =
        math.max(_startupDiagnosticsMaxPeak, rawStats.peak);
    final int nextAt = _startupDiagnosticsNextAtMillis ?? now;
    if (now < nextAt) return;

    print(
      '[VoiceCapture#$_captureId] startup audio offsetMs=$offsetMs '
      'chunks=$_startupDiagnosticsChunks '
      'rawRms=${rawStats.rms.toStringAsFixed(5)} '
      'rawPeak=${rawStats.peak.toStringAsFixed(5)} '
      'postGainRms=${postGainStats.rms.toStringAsFixed(5)} '
      'postGainPeak=${postGainStats.peak.toStringAsFixed(5)} '
      'windowMaxRms=${_startupDiagnosticsMaxRms.toStringAsFixed(5)} '
      'windowMaxPeak=${_startupDiagnosticsMaxPeak.toStringAsFixed(5)}',
    );
    _startupDiagnosticsNextAtMillis = now + _startupDiagnosticsIntervalMs;
    _startupDiagnosticsChunks = 0;
    _startupDiagnosticsMaxRms = 0.0;
    _startupDiagnosticsMaxPeak = 0.0;
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
