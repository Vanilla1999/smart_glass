import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:smart_glasses/core/voice/native_voice_capture.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_device_profile.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_startup_wav_capture.dart';

class AudioStreamService {
  static const double _liveGainMultiplier = 1.0;
  static const double _noiseFloor = 0.03;
  static const double _attackSmoothing = 0.45;
  static const double _releaseSmoothing = 0.15;
  static const int _startupDiagnosticsDurationMs = 10000;
  static const int _startupDiagnosticsIntervalMs = 500;
  static const Duration _startupWavDuration = Duration(seconds: 8);

  AudioStreamService({
    VoiceDeviceProfile? deviceProfile,
    NativeVoiceCapture? nativeCapture,
    this.recordContinuousWav = false,
  })  : _deviceProfile = deviceProfile ?? VoiceDeviceProfile.resolve(),
        _nativeCapture = nativeCapture ?? NativeVoiceCapture.instance;

  VoiceDeviceProfile _deviceProfile;
  final NativeVoiceCapture _nativeCapture;
  final bool recordContinuousWav;
  final StreamController<double> _audioLevelController =
      StreamController<double>.broadcast();
  bool _isRunning = false;
  double _audioLevel = 0.0;
  int _chunksReceived = 0;
  int? _lastChunkAtMillis;
  int? _lastNonSilentChunkAtMillis;
  int? _lastNonZeroNativeInputAtMillis;
  int? _continuousZeroAudioStartedAtMillis;
  int? _startedAtMillis;
  int? _startupDiagnosticsStartedAtMillis;
  int? _startupDiagnosticsNextAtMillis;
  int _startupDiagnosticsChunks = 0;
  double _startupDiagnosticsMaxRms = 0.0;
  double _startupDiagnosticsMaxPeak = 0.0;
  int _captureId = 0;
  int? _leaseId;
  VoiceStartupWavCapture? _startupWavCapture;
  String? _startupWavPath;
  bool _startupWavSaved = false;
  RandomAccessFile? _continuousWavFile;
  String? _continuousWavPath;
  int? _continuousWavTimestamp;
  int _continuousWavPcmBytes = 0;
  int _continuousWavBytesSinceHeaderUpdate = 0;
  Future<void> _lifecycleOperation = Future<void>.value();
  Future<void>? _pendingStart;
  int _lifecycleGeneration = 0;

  final List<void Function(Uint8List)> _dataCallbacks = [];
  final List<FutureOr<bool> Function(Uint8List raw, Uint8List boosted)>
      _pcmCallbacks = [];

  bool get isRunning => _isRunning;
  double get audioLevel => _audioLevel;
  int get chunksReceived => _chunksReceived;
  int? get lastChunkAtMillis => _lastChunkAtMillis;
  int? get lastNonSilentChunkAtMillis => _lastNonSilentChunkAtMillis;
  int? get lastNonZeroNativeInputAtMillis => _lastNonZeroNativeInputAtMillis;
  int? get continuousZeroAudioStartedAtMillis =>
      _continuousZeroAudioStartedAtMillis;
  int? get captureStartedAtMillis => _startedAtMillis;
  int get captureId => _captureId;
  VoiceDeviceProfile get deviceProfile => _deviceProfile;
  String? get preferredInputDeviceId => 'uac4';
  String? get preferredInputDeviceLabel => 'UAC4 four-microphone service';
  bool get hasExpectedInputDevice => true;
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
    FutureOr<bool> Function(Uint8List raw, Uint8List boosted) callback,
  ) {
    if (!_pcmCallbacks.contains(callback)) _pcmCallbacks.add(callback);
  }

  void removePcmCallback(
    FutureOr<bool> Function(Uint8List raw, Uint8List boosted) callback,
  ) {
    _pcmCallbacks.remove(callback);
  }

  Future<bool> requestPermission() {
    return _nativeCapture.requestPermission();
  }

  Future<bool> refreshNativeInputActivity() async {
    final Map<String, Object?> diagnostics =
        await _nativeCapture.getDiagnostics();
    final Object? channelsValue = diagnostics['inputChannels'];
    if (channelsValue is! List) return false;
    final bool active = channelsValue.whereType<Map>().any(
          (channel) => (channel['peak'] as num?)?.toDouble() != 0.0,
        );
    if (active) {
      _lastNonZeroNativeInputAtMillis = DateTime.now().millisecondsSinceEpoch;
    }
    return active;
  }

  Future<String> diagnostics() async {
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
        'registeredDataConsumers=${_dataCallbacks.length}, '
        'registeredPcmConsumers=${_pcmCallbacks.length}, '
        'receivedPcmPackets=$_chunksReceived, lastChunkAgeMs=$lastChunkAgeMs, '
        'lastNonSilentAgeMs=$lastNonSilentAgeMs, '
        'continuousZeroAudioAgeMs=$continuousZeroAudioAgeMs, '
        'inputDevice=UAC4, '
        'startupWavPath=$_startupWavPath '
        'startupWavBytes=${_startupWavCapture?.pcmBytes}, '
        'runningForMs=$runningForMs}';
  }

  Future<void> start({
    void Function(Uint8List bytes)? onData,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    final Future<void>? pending = _pendingStart;
    if (pending != null) return pending;
    final int generation = ++_lifecycleGeneration;
    late final Future<void> next;
    next = _serializeLifecycle(() async {
      if (_isRunning) {
        print(
          '[AudioStreamService] start called while running; '
          'registeredDataConsumers=${_dataCallbacks.length} '
          'registeredPcmConsumers=${_pcmCallbacks.length}',
        );
        if (onData != null) {
          addDataCallback(onData);
        }
        if (onError != null) {}
        return;
      }

      _captureId++;
      _chunksReceived = 0;
      _lastChunkAtMillis = null;
      _continuousZeroAudioStartedAtMillis = null;
      _lastNonZeroNativeInputAtMillis = null;
      _startedAtMillis = null;
      _lastNonSilentChunkAtMillis = null;
      if (onData != null) {
        addDataCallback(onData);
      }
      if (onError != null) {}

      await _beginContinuousWavRecording();

      final int leaseId = await _nativeCapture.start(
        owner: NativeVoiceOwner.wearRecognition,
        recordDiagnosticWav: recordContinuousWav,
        diagnosticCaptureTimestamp: _continuousWavTimestamp,
        onPcm: (NativePcmPacket packet) async {
          final Uint8List bytes = packet.bytes;
          if (bytes.lengthInBytes < 2) {
            print('[VoiceCapture#$_captureId] ignored empty PCM stream event');
            return false;
          }
          final _PcmStats rawStats = _pcmStats(bytes);
          _captureStartupWav(bytes);
          await _writeContinuousWav(bytes);
          final boostedBytes = _boostPcm16(bytes);
          _chunksReceived++;
          _lastChunkAtMillis = DateTime.now().millisecondsSinceEpoch;
          final _PcmStats stats = _pcmStats(boostedBytes);
          _logStartupDiagnostics(rawStats, stats);
          if (rawStats.peak > 0.0) {
            _lastNonSilentChunkAtMillis = _lastChunkAtMillis;
          }
          if (rawStats.peak == 0.0) {
            _continuousZeroAudioStartedAtMillis ??= _lastChunkAtMillis;
          } else {
            _continuousZeroAudioStartedAtMillis = null;
          }
          if (_chunksReceived == 1 || _chunksReceived % 200 == 0) {
            print(
              '[VoiceCapture#$_captureId] chunk#$_chunksReceived '
              'bytes=${boostedBytes.lengthInBytes} '
              'registeredDataConsumers=${_dataCallbacks.length} '
              'registeredPcmConsumers=${_pcmCallbacks.length} '
              'rawRms=${rawStats.rms.toStringAsFixed(5)} '
              'rawPeak=${rawStats.peak.toStringAsFixed(5)} '
              'postGainRms=${stats.rms.toStringAsFixed(5)} '
              'postGainPeak=${stats.peak.toStringAsFixed(5)} '
              'at=$_lastChunkAtMillis',
            );
          }
          _publishAudioLevel(boostedBytes);
          for (final cb in List<void Function(Uint8List)>.of(_dataCallbacks)) {
            cb(boostedBytes);
          }
          for (final cb
              in List<FutureOr<bool> Function(Uint8List, Uint8List)>.of(
            _pcmCallbacks,
          )) {
            if (!await cb(bytes, boostedBytes)) return false;
          }
          return true;
        },
      );

      if (generation != _lifecycleGeneration) {
        await _nativeCapture.stop(
          owner: NativeVoiceOwner.wearRecognition,
          leaseId: leaseId,
        );
        return;
      }
      _leaseId = leaseId;
      _startedAtMillis = DateTime.now().millisecondsSinceEpoch;
      _beginStartupDiagnostics();
      await _beginStartupWavCapture();
      _isRunning = true;
      print(
        '[VoiceCapture#$_captureId] start at $_startedAtMillis '
        'profile=${_deviceProfile.id}',
      );
      print('[VoiceCapture#$_captureId] control started; waiting for PCM');
    }).whenComplete(() {
      if (identical(_pendingStart, next)) _pendingStart = null;
    });
    _pendingStart = next;
    return next;
  }

  Future<void> stop() {
    _lifecycleGeneration++;
    return _serializeLifecycle(() async {
      print('[VoiceCapture#$_captureId] stop begin: ${await diagnostics()}');
      final int? leaseId = _leaseId;
      try {
        if (leaseId != null) {
          await _nativeCapture.stop(
            owner: NativeVoiceOwner.wearRecognition,
            leaseId: leaseId,
          );
        }
      } finally {
        await _closeContinuousWavRecording();
      }
      _leaseId = null;

      _dataCallbacks.clear();
      _pcmCallbacks.clear();
      _isRunning = false;
      _startedAtMillis = null;
      _continuousZeroAudioStartedAtMillis = null;
      _setAudioLevel(0.0);
      print('[VoiceCapture#$_captureId] stop done');
    });
  }

  Future<void> recreateRecorder() async {
    await stop();
    print('[VoiceCapture#$_captureId] native capture lease released');
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
        'registeredDataConsumers=${_dataCallbacks.length} '
        'registeredPcmConsumers=${_pcmCallbacks.length}');
    _dataCallbacks.clear();
    _pcmCallbacks.clear();
  }

  Future<void> dispose() async {
    await stop();
    await _closeContinuousWavRecording();
    await _audioLevelController.close();
  }

  Future<void> _beginContinuousWavRecording() async {
    if (!recordContinuousWav || _continuousWavFile != null) return;

    final Directory? externalDirectory = await getExternalStorageDirectory();
    if (externalDirectory == null) {
      throw StateError('External storage is unavailable for voice recording.');
    }
    final Directory directory =
        Directory('${externalDirectory.path}/voice_capture');
    await directory.create(recursive: true);
    final int timestamp = DateTime.now().millisecondsSinceEpoch;
    _continuousWavTimestamp = timestamp;
    _continuousWavPath = '${directory.path}/ssp_mono_$timestamp.wav';
    _continuousWavFile =
        await File(_continuousWavPath!).open(mode: FileMode.write);
    _continuousWavPcmBytes = 0;
    _continuousWavBytesSinceHeaderUpdate = 0;
    await _continuousWavFile!.writeFrom(_wavHeader(0));
    await _continuousWavFile!.flush();
    print(
        '[AudioStreamService] continuous WAV recording path=$_continuousWavPath');
  }

  Future<void> _writeContinuousWav(Uint8List bytes) async {
    final RandomAccessFile? file = _continuousWavFile;
    if (file == null) return;

    await file.writeFrom(bytes);
    _continuousWavPcmBytes += bytes.lengthInBytes;
    _continuousWavBytesSinceHeaderUpdate += bytes.lengthInBytes;
    if (_continuousWavBytesSinceHeaderUpdate < 32000) return;

    _continuousWavBytesSinceHeaderUpdate = 0;
    final int endPosition = await file.position();
    await file.setPosition(0);
    await file.writeFrom(_wavHeader(_continuousWavPcmBytes));
    await file.setPosition(endPosition);
    await file.flush();
  }

  Future<void> _closeContinuousWavRecording() async {
    final RandomAccessFile? file = _continuousWavFile;
    if (file == null) return;
    await file.setPosition(0);
    await file.writeFrom(_wavHeader(_continuousWavPcmBytes));
    await file.flush();
    await file.close();
    _continuousWavFile = null;
  }

  Uint8List _wavHeader(int pcmBytes) {
    final Uint8List header = Uint8List(44);
    final ByteData data = ByteData.sublistView(header);
    header.setRange(0, 4, 'RIFF'.codeUnits);
    data.setUint32(4, 36 + pcmBytes, Endian.little);
    header.setRange(8, 12, 'WAVE'.codeUnits);
    header.setRange(12, 16, 'fmt '.codeUnits);
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, 16000, Endian.little);
    data.setUint32(28, 32000, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    header.setRange(36, 40, 'data'.codeUnits);
    data.setUint32(40, pcmBytes, Endian.little);
    return header;
  }

  Future<void> _serializeLifecycle(Future<void> Function() operation) {
    final Future<void> next = _lifecycleOperation.then((_) => operation());
    _lifecycleOperation = next.catchError((Object _, StackTrace __) {});
    return next;
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
      'receivedPcmPackets=$_startupDiagnosticsChunks '
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

class VoiceInputDeviceUnavailable implements Exception {
  const VoiceInputDeviceUnavailable();

  @override
  String toString() =>
      'VoiceInputDeviceUnavailable: USB-Audio - UVC input is unavailable.';
}

class VoiceInputDeviceAmbiguous implements Exception {
  const VoiceInputDeviceAmbiguous(this.labels);

  final Iterable<String> labels;

  @override
  String toString() => 'VoiceInputDeviceAmbiguous: ${labels.join(', ')}';
}
