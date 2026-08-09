import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:smart_glasses/core/voice/native_voice_capture.dart';

/// Test-only replacement for UAC4 capture that replays recorded PCM packets.
class ReplayVoiceCapture implements NativeVoiceCapturePort {
  ReplayVoiceCapture({
    int? startTimestampMicros,
    this.terminateOnRejectedAcknowledgement = true,
  }) : startTimestampMicros =
            startTimestampMicros ?? DateTime.now().microsecondsSinceEpoch;

  final int startTimestampMicros;
  final bool terminateOnRejectedAcknowledgement;
  final List<bool> acknowledgements = <bool>[];
  final NativePcmPacketEndpoint _endpoint = NativePcmPacketEndpoint();
  NativeVoiceOwner? _owner;
  int? _leaseId;
  int _nextLeaseId = 1;
  int _nextSequence = 0;
  late int _lastTimestampMicros = startTimestampMicros;
  int _lastElapsedRealtimeNanos = 0;

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
    _nextSequence = 0;
    _lastTimestampMicros = startTimestampMicros;
    _lastElapsedRealtimeNanos = 0;
    _leaseId = _nextLeaseId++;
    _endpoint
      ..beginSession(
        leaseId: _leaseId!,
        revision: _leaseId!,
        consumer: onPcm,
      )
      ..markStreaming();
    return _leaseId!;
  }

  @override
  Future<void> stop({
    required NativeVoiceOwner owner,
    required int leaseId,
  }) async {
    if (_leaseId != leaseId || _owner != owner) return;
    _endpoint.endSession();
    _owner = null;
    _leaseId = null;
  }

  Future<bool> emit(
    Uint8List pcm, {
    int? sequence,
    int? elapsedRealtimeNanos,
    int? capturedAtEpochMicros,
  }) async {
    final int? leaseId = _leaseId;
    if (leaseId == null) {
      throw StateError('Replay capture is not active.');
    }
    final int packetSequence = sequence ?? _nextSequence;
    _nextSequence = packetSequence + 1;
    final int nowMicros = DateTime.now().microsecondsSinceEpoch;
    final int micros = capturedAtEpochMicros ??
        (nowMicros > _lastTimestampMicros
            ? nowMicros
            : _lastTimestampMicros + 1);
    _lastTimestampMicros = micros;
    final int packetDurationNanos =
        pcm.lengthInBytes * 1000000000 ~/ (16000 * 2);
    final int elapsedNanos = elapsedRealtimeNanos ??
        (_lastElapsedRealtimeNanos == 0
            ? packetDurationNanos
            : _lastElapsedRealtimeNanos + packetDurationNanos);
    _lastElapsedRealtimeNanos = elapsedNanos;
    final ByteData packet = ByteData(40 + pcm.lengthInBytes)
      ..setUint32(0, 2, Endian.big)
      ..setUint32(4, 40, Endian.big)
      ..setInt64(8, leaseId, Endian.big)
      ..setInt64(16, packetSequence, Endian.big)
      ..setInt64(24, elapsedNanos, Endian.big)
      ..setInt64(32, micros, Endian.big);
    packet.buffer.asUint8List().setRange(40, 40 + pcm.lengthInBytes, pcm);
    final ByteData acknowledgement = await _endpoint.handle(packet);
    final bool accepted = acknowledgement.getUint32(4, Endian.big) ==
        NativePcmPacketEndpoint.accepted;
    acknowledgements.add(accepted);
    if (!accepted && terminateOnRejectedAcknowledgement) {
      await stop(owner: _owner!, leaseId: leaseId);
    }
    return accepted;
  }

  Future<void> replay(
    Iterable<Uint8List> packets, {
    bool realTime = true,
  }) async {
    for (final Uint8List packet in packets) {
      await emit(packet);
      if (realTime) {
        await Future<void>.delayed(Duration(
          microseconds: packet.lengthInBytes * 1000000 ~/ (16000 * 2),
        ));
      }
    }
  }

  /// Reads PCM16 mono/16 kHz WAV data in native mono transport packet sizes.
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
    bool validFormat = false;
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
        validFormat = true;
      } else if (id == 'data') {
        pcm = Uint8List.sublistView(bytes, body, body + length);
        break;
      }
      offset = body + length + (length.isOdd ? 1 : 0);
    }
    if (!validFormat || pcm == null || pcm.isEmpty || pcm.lengthInBytes.isOdd) {
      throw const FormatException('WAV file has no valid PCM data.');
    }
    const int packetBytes = 1024;
    return <Uint8List>[
      for (int offset = 0; offset < pcm.lengthInBytes; offset += packetBytes)
        Uint8List.fromList(
          pcm.sublist(
              offset, (offset + packetBytes).clamp(0, pcm.lengthInBytes)),
        ),
    ];
  }
}
