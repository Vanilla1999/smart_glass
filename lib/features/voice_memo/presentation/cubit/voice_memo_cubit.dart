import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:smart_glasses/core/voice/native_voice_capture.dart';
import 'package:smart_glasses/features/voice_memo/presentation/cubit/voice_memo_state.dart';

class VoiceMemoCubit extends Cubit<VoiceMemoState> {
  VoiceMemoCubit(this._nativeCapture) : super(const VoiceMemoIdle());

  static const _normalizationTarget = 0.98;
  static const int _maxPendingPcmBytes = 64000;
  static const Duration _drainTimeout = Duration(seconds: 5);

  final NativeVoiceCapture _nativeCapture;
  RandomAccessFile? _file;
  String? _temporaryPath;
  int? _leaseId;
  int _pcmBytes = 0;
  int _pendingPcmBytes = 0;
  Future<void> _writeQueue = Future<void>.value();
  int _finalizationGeneration = 0;
  Future<void> _lifecycleOperation = Future<void>.value();
  int _lifecycleGeneration = 0;

  Future<String> _getVoiceMemosDir() async {
    final base = await getExternalStorageDirectory();
    final dir = Directory('${base!.path}/VoiceMemos');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  Future<void> startRecording() {
    final int generation = ++_lifecycleGeneration;
    return _serializeLifecycle(() => _startRecording(generation));
  }

  Future<void> _startRecording(int generation) async {
    if (_leaseId != null) return;
    final hasPermission = await _nativeCapture.requestPermission();
    if (generation != _lifecycleGeneration) return;
    if (!hasPermission) {
      emit(const VoiceMemoError(message: 'Нет разрешения на микрофон'));
      return;
    }

    String dirPath;
    try {
      dirPath = await _getVoiceMemosDir();
    } catch (e) {
      dirPath = Directory.systemTemp.path;
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '$dirPath/voice_memo_$timestamp.wav';
    final temporaryPath = '$path.tmp';

    try {
      _temporaryPath = temporaryPath;
      _pcmBytes = 0;
      _pendingPcmBytes = 0;
      _writeQueue = Future<void>.value();
      _file = await File(temporaryPath).open(mode: FileMode.write);
      await _file!.writeFrom(_wavHeader(0));
      final int leaseId = await _nativeCapture.start(
        owner: NativeVoiceOwner.voiceMemo,
        onPcm: (NativePcmPacket packet) => _admitPcm(packet.bytes),
      );
      if (generation != _lifecycleGeneration) {
        await _nativeCapture.stop(
          owner: NativeVoiceOwner.voiceMemo,
          leaseId: leaseId,
        );
        await _closeFile();
        await _deleteTemporary();
        return;
      }
      _leaseId = leaseId;
      emit(const VoiceMemoRecording());
    } catch (e) {
      await _closeFile();
      try {
        await File(temporaryPath).delete();
      } on FileSystemException {
        // The temporary file may not have been created before UAC4 startup failed.
      }
      _temporaryPath = null;
      emit(VoiceMemoError(message: 'Ошибка записи: $e'));
    }
  }

  Future<void> stopAndSave() {
    _lifecycleGeneration++;
    return _serializeLifecycle(_stopAndSaveBounded);
  }

  Future<void> _stopAndSaveBounded() async {
    final int generation = ++_finalizationGeneration;
    try {
      await _stopAndSave(generation).timeout(_drainTimeout);
    } catch (e) {
      _finalizationGeneration++;
      await _closeFile();
      await _deleteTemporary();
      emit(VoiceMemoError(message: 'Ошибка сохранения: $e'));
    }
  }

  Future<void> _stopAndSave(int generation) async {
    final int? leaseId = _leaseId;
    if (leaseId == null || _temporaryPath == null) {
      throw StateError('Запись не запущена');
    }
    await _nativeCapture.stop(
      owner: NativeVoiceOwner.voiceMemo,
      leaseId: leaseId,
    );
    _leaseId = null;
    await _writeQueue;
    if (generation != _finalizationGeneration) return;
    final RandomAccessFile file = _file!;
    await file.setPosition(0);
    await file.writeFrom(_wavHeader(_pcmBytes));
    await file.flush();
    await _closeFile();
    if (generation != _finalizationGeneration) return;
    final String result = _temporaryPath!.replaceFirst(RegExp(r'\.tmp$'), '');
    final File temporary = File(_temporaryPath!);
    await temporary.rename(result);
    if (generation != _finalizationGeneration) {
      await File(result).delete();
      return;
    }
    if (_pcmBytes > 0) {
      final normalizedPath = await _normalizeWavFile(result);
      if (generation != _finalizationGeneration) {
        await File(result).delete();
        return;
      }
      _temporaryPath = null;
      emit(VoiceMemoSaved(filePath: normalizedPath));
    } else {
      await File(result).delete();
      _temporaryPath = null;
      emit(const VoiceMemoError(message: 'Не удалось сохранить запись'));
    }
  }

  void reset() {
    emit(const VoiceMemoIdle());
  }

  bool _admitPcm(Uint8List bytes) {
    if (_file == null ||
        _pendingPcmBytes + bytes.lengthInBytes > _maxPendingPcmBytes) {
      unawaited(_abortRecording());
      return false;
    }
    _pendingPcmBytes += bytes.lengthInBytes;
    final Uint8List admitted = Uint8List.fromList(bytes);
    _writeQueue = _writeQueue.then((_) async {
      final RandomAccessFile? file = _file;
      if (file == null) throw StateError('Voice memo file is closed.');
      await file.writeFrom(admitted);
      _pcmBytes += bytes.lengthInBytes;
    }).whenComplete(() {
      _pendingPcmBytes -= bytes.lengthInBytes;
    });
    return true;
  }

  Future<void> handleNativeVoiceState(NativeVoiceStateEvent event) {
    if (event.owner != NativeVoiceOwner.voiceMemo ||
        event.leaseId != _leaseId ||
        (event.state != NativeVoiceCaptureState.error &&
            event.state != NativeVoiceCaptureState.terminalAbandoned &&
            event.state != NativeVoiceCaptureState.disposed)) {
      return Future<void>.value();
    }
    return _serializeLifecycle(() => _handleNativeVoiceState(event));
  }

  Future<void> _handleNativeVoiceState(NativeVoiceStateEvent event) async {
    _leaseId = null;
    _finalizationGeneration++;
    try {
      await _writeQueue.timeout(_drainTimeout);
    } catch (_) {
      // Cleanup below owns the incomplete recording after a native failure.
    }
    await _closeFile();
    await _deleteTemporary();
    emit(VoiceMemoError(
      message: 'Запись остановлена: ${event.errorCode ?? 'ошибка микрофона'}',
    ));
  }

  Future<void> _serializeLifecycle(Future<void> Function() operation) {
    final Future<void> next = _lifecycleOperation.then((_) => operation());
    _lifecycleOperation = next.catchError((Object _, StackTrace __) {});
    return next;
  }

  Future<void> _abortRecording() {
    _lifecycleGeneration++;
    return _serializeLifecycle(_abortRecordingUnlocked);
  }

  Future<void> _abortRecordingUnlocked() async {
    final int? leaseId = _leaseId;
    try {
      if (leaseId != null) {
        await _nativeCapture.stop(
            owner: NativeVoiceOwner.voiceMemo, leaseId: leaseId);
      }
      _leaseId = null;
      await _writeQueue.timeout(_drainTimeout);
    } catch (_) {
      // The native bridge terminates a lease that rejects PCM admission.
      _leaseId = null;
    }
    await _closeFile();
    await _deleteTemporary();
    emit(const VoiceMemoError(message: 'Очередь записи переполнена'));
  }

  Future<void> _deleteTemporary() async {
    final String? path = _temporaryPath;
    _temporaryPath = null;
    if (path == null) return;
    try {
      await File(path).delete();
    } on FileSystemException {
      // The temporary file may not exist when capture startup fails.
    }
    if (path.endsWith('.tmp')) {
      try {
        await File(path.substring(0, path.length - 4)).delete();
      } on FileSystemException {
        // A failed finalization may not have reached the atomic rename.
      }
    }
  }

  Future<void> _closeFile() async {
    final RandomAccessFile? file = _file;
    _file = null;
    if (file == null) return;
    try {
      await file.close();
    } on FileSystemException {
      // Cleanup remains idempotent after a failed write or timeout.
    }
  }

  Future<String> _normalizeWavFile(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    final dataOffset = _findWavDataOffset(bytes);
    if (dataOffset == null) {
      return path;
    }

    final data = ByteData.sublistView(bytes);
    var peak = 0;
    for (var offset = dataOffset; offset + 1 < bytes.length; offset += 2) {
      final sample = data.getInt16(offset, Endian.little);
      final absolute = sample == -32768 ? 32768 : sample.abs();
      if (absolute > peak) {
        peak = absolute;
      }
    }

    if (peak == 0) {
      return path;
    }

    final multiplier = (32767 * _normalizationTarget) / peak;
    if (multiplier <= 1) {
      return path;
    }

    for (var offset = dataOffset; offset + 1 < bytes.length; offset += 2) {
      final sample = data.getInt16(offset, Endian.little);
      final normalized = (sample * multiplier).round().clamp(-32768, 32767);
      data.setInt16(offset, normalized, Endian.little);
    }

    await file.writeAsBytes(bytes, flush: true);
    return path;
  }

  Uint8List _wavHeader(int pcmBytes) {
    final header = ByteData(44);
    void ascii(int offset, String value) {
      for (var index = 0; index < value.length; index++) {
        header.setUint8(offset + index, value.codeUnitAt(index));
      }
    }

    ascii(0, 'RIFF');
    header.setUint32(4, 36 + pcmBytes, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, 16000, Endian.little);
    header.setUint32(28, 32000, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    header.setUint32(40, pcmBytes, Endian.little);
    return header.buffer.asUint8List();
  }

  int? _findWavDataOffset(Uint8List bytes) {
    if (bytes.length < 44 || !_matchesAscii(bytes, 0, 'RIFF')) {
      return null;
    }
    if (!_matchesAscii(bytes, 8, 'WAVE')) {
      return null;
    }

    final data = ByteData.sublistView(bytes);
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      if (_matchesAscii(bytes, offset, 'data')) {
        return offset + 8;
      }

      final nextOffset = offset + 8 + chunkSize + (chunkSize.isOdd ? 1 : 0);
      if (nextOffset <= offset || nextOffset > bytes.length) {
        return null;
      }
      offset = nextOffset;
    }

    return null;
  }

  bool _matchesAscii(Uint8List bytes, int offset, String value) {
    if (offset + value.length > bytes.length) {
      return false;
    }
    for (var i = 0; i < value.length; i++) {
      if (bytes[offset + i] != value.codeUnitAt(i)) {
        return false;
      }
    }
    return true;
  }

  @override
  Future<void> close() async {
    _lifecycleGeneration++;
    await _serializeLifecycle(() async {
      if (_leaseId != null) {
        await _stopAndSaveBounded();
        return;
      }
      _finalizationGeneration++;
      try {
        await _writeQueue.timeout(_drainTimeout);
      } catch (_) {
        // Closing a Cubit never publishes an incomplete memo.
      }
      await _closeFile();
      await _deleteTemporary();
    });
    await super.close();
  }
}
