import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart' as rec;
import 'package:smart_glasses/features/voice_memo/presentation/cubit/voice_memo_state.dart';

class VoiceMemoCubit extends Cubit<VoiceMemoState> {
  VoiceMemoCubit() : super(const VoiceMemoIdle());

  static const _normalizationTarget = 0.98;

  final _recorder = rec.AudioRecorder();

  Future<String> _getVoiceMemosDir() async {
    final base = await getExternalStorageDirectory();
    final dir = Directory('${base!.path}/VoiceMemos');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  Future<void> startRecording() async {
    final hasPermission = await _recorder.hasPermission();
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

    try {
      await _recorder.start(
        rec.RecordConfig(
          encoder: rec.AudioEncoder.wav,
          sampleRate: 44100,
          numChannels: 1,
          androidConfig: const rec.AndroidRecordConfig(
            audioSource: rec.AndroidAudioSource.mic,
          ),
        ),
        path: path,
      );
      emit(const VoiceMemoRecording());
    } catch (e) {
      emit(VoiceMemoError(message: 'Ошибка записи: $e'));
    }
  }

  Future<void> stopAndSave() async {
    try {
      final result = await _recorder.stop();
      if (result != null && result.isNotEmpty) {
        final normalizedPath = await _normalizeWavFile(result);
        emit(VoiceMemoSaved(filePath: normalizedPath));
      } else {
        emit(const VoiceMemoError(message: 'Не удалось сохранить запись'));
      }
    } catch (e) {
      emit(VoiceMemoError(message: 'Ошибка сохранения: $e'));
    }
  }

  void reset() {
    emit(const VoiceMemoIdle());
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
      final normalized = (sample * multiplier)
          .round()
          .clamp(-32768, 32767);
      data.setInt16(offset, normalized, Endian.little);
    }

    await file.writeAsBytes(bytes, flush: true);
    return path;
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
  Future<void> close() {
    _recorder.dispose();
    return super.close();
  }
}
