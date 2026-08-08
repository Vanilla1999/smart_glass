import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:smart_glasses/core/voice/native_voice_capture.dart';

/// Test-only replacement for UAC4 capture that replays recorded PCM packets.
class ReplayVoiceCapture implements NativeVoiceCapturePort {
  ReplayVoiceCapture({int? startTimestampMicros})
      : startTimestampMicros =
            startTimestampMicros ?? DateTime.now().microsecondsSinceEpoch;

  final int startTimestampMicros;
  final List<bool> acknowledgements = <bool>[];
  NativePcmConsumer? _consumer;
  NativeVoiceOwner? _owner;
  int? _leaseId;
  int _nextSequence = 0;
  late int _lastTimestampMicros = startTimestampMicros;

  bool get isCapturing => _leaseId != null;

  @override
  Future<Map<String, Object?>> getDiagnostics() async => <String, Object?>{
        'inputChannels': const <Map<String, Object?>>[
          <String, Object?>{'channel': 0, 'peak': 1.0},
        ],
      };

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<int> start({
    required NativeVoiceOwner owner,
    required NativePcmConsumer onPcm,
    bool recordDiagnosticWav = false,
    int? diagnosticCaptureTimestamp,
  }) async {
    if (_leaseId != null) throw StateError('Replay capture is already active.');
    _owner = owner;
    _consumer = onPcm;
    _nextSequence = 0;
    _lastTimestampMicros = startTimestampMicros;
    _leaseId = 1;
    return _leaseId!;
  }

  @override
  Future<void> stop({
    required NativeVoiceOwner owner,
    required int leaseId,
  }) async {
    if (_leaseId != leaseId || _owner != owner) return;
    _consumer = null;
    _owner = null;
    _leaseId = null;
  }

  Future<bool> emit(Uint8List pcm,
      {int? sequence, int? timestampMicros}) async {
    final NativePcmConsumer? consumer = _consumer;
    final int? leaseId = _leaseId;
    if (consumer == null || leaseId == null) {
      throw StateError('Replay capture is not active.');
    }
    final int packetSequence = sequence ?? _nextSequence++;
    final int nowMicros = DateTime.now().microsecondsSinceEpoch;
    final int micros = timestampMicros ??
        (nowMicros > _lastTimestampMicros
            ? nowMicros
            : _lastTimestampMicros + 1);
    _lastTimestampMicros = micros;
    final bool accepted = await consumer(NativePcmPacket(
      leaseId: leaseId,
      sequence: packetSequence,
      elapsedRealtimeNanos: micros * 1000,
      capturedAtEpochMicros: micros,
      bytes: pcm,
    ));
    acknowledgements.add(accepted);
    return accepted;
  }

  Future<void> replay(Iterable<Uint8List> packets) async {
    for (final Uint8List packet in packets) {
      await emit(packet);
    }
  }

  /// Reads PCM16 mono/16 kHz WAV data and returns 20 ms packets (640 bytes).
  static Future<List<Uint8List>> readMono16kWav(File file) async {
    final Uint8List bytes = await file.readAsBytes();
    if (bytes.lengthInBytes < 44 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      throw const FormatException('Expected a RIFF/WAVE file.');
    }
    final ByteData data = ByteData.sublistView(bytes);
    int offset = 12;
    Uint8List? pcm;
    while (offset + 8 <= bytes.lengthInBytes) {
      final String id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final int length = data.getUint32(offset + 4, Endian.little);
      final int body = offset + 8;
      if (body + length > bytes.lengthInBytes) break;
      if (id == 'fmt ') {
        if (length < 16 ||
            data.getUint16(body, Endian.little) != 1 ||
            data.getUint16(body + 2, Endian.little) != 1 ||
            data.getUint32(body + 4, Endian.little) != 16000 ||
            data.getUint16(body + 14, Endian.little) != 16) {
          throw const FormatException('Expected PCM16 mono at 16 kHz.');
        }
      } else if (id == 'data') {
        pcm = Uint8List.sublistView(bytes, body, body + length);
        break;
      }
      offset = body + length + (length.isOdd ? 1 : 0);
    }
    if (pcm == null || pcm.isEmpty || pcm.lengthInBytes.isOdd) {
      throw const FormatException('WAV file has no valid PCM data.');
    }
    const int packetBytes = 640;
    return <Uint8List>[
      for (int offset = 0; offset < pcm.lengthInBytes; offset += packetBytes)
        Uint8List.fromList(
          pcm.sublist(
              offset, (offset + packetBytes).clamp(0, pcm.lengthInBytes)),
        ),
    ];
  }
}
