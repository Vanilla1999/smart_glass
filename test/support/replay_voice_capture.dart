import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:smart_glasses/core/voice/native_voice_capture.dart';

typedef ReplayPcmAcknowledgement = ({
  int status,
  int leaseId,
  int sequence,
});

abstract interface class ReplayTimeline {
  Duration get elapsed;
  void reset();
  Future<void> delay(Duration duration);
}

class WallClockReplayTimeline implements ReplayTimeline {
  final Stopwatch _stopwatch = Stopwatch();

  @override
  Duration get elapsed => _stopwatch.elapsed;

  @override
  void reset() {
    _stopwatch
      ..reset()
      ..start();
  }

  @override
  Future<void> delay(Duration duration) => Future<void>.delayed(duration);
}

/// Test-only replacement for UAC4 capture that replays recorded PCM packets.
class ReplayVoiceCapture
    implements NativeVoiceCapturePort, NativeVoiceStateSource {
  ReplayVoiceCapture({
    int? startTimestampMicros,
    this.terminateOnRejectedAcknowledgement = true,
    ReplayTimeline? timeline,
  })  : startTimestampMicros =
            startTimestampMicros ?? DateTime.now().microsecondsSinceEpoch,
        _timeline = timeline ?? WallClockReplayTimeline();

  final int startTimestampMicros;
  final bool terminateOnRejectedAcknowledgement;
  final ReplayTimeline _timeline;
  final List<bool> acknowledgements = <bool>[];
  final List<ReplayPcmAcknowledgement> acknowledgementRecords =
      <ReplayPcmAcknowledgement>[];
  final NativePcmPacketEndpoint _endpoint = NativePcmPacketEndpoint();
  final StreamController<NativeVoiceStateEvent> _stateController =
      StreamController<NativeVoiceStateEvent>.broadcast(sync: true);
  NativeVoiceOwner? _owner;
  int? _leaseId;
  int _nextLeaseId = 1;
  int _revision = 0;
  int? _lastTerminalLeaseId;
  int? _lastTerminalRevision;
  int _nextSequence = 0;
  late int _lastTimestampMicros = startTimestampMicros;
  int _lastElapsedRealtimeNanos = 0;

  bool get isCapturing => _leaseId != null;
  Stream<NativeVoiceStateEvent> get stateEvents => _stateController.stream;

  @override
  bool isOwnedBy(NativeVoiceOwner owner) => _owner == owner;

  @override
  bool isRelevantStateEvent(NativeVoiceStateEvent event) {
    if (event.leaseId != null) {
      return event.leaseId == _lastTerminalLeaseId &&
          event.revision == _lastTerminalRevision;
    }
    return _owner != null && event.revision >= _revision;
  }

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
    final int revision = ++_revision;
    _lastTerminalLeaseId = null;
    _lastTerminalRevision = null;
    _endpoint
      ..beginSession(
        leaseId: _leaseId!,
        revision: revision,
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
    _clearActiveCapture(advanceRevision: true);
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
    final int status = acknowledgement.getUint32(4, Endian.big);
    final ReplayPcmAcknowledgement record = (
      status: status,
      leaseId: acknowledgement.getInt64(8, Endian.big),
      sequence: acknowledgement.getInt64(16, Endian.big),
    );
    acknowledgementRecords.add(record);
    final bool accepted = status == NativePcmPacketEndpoint.accepted;
    acknowledgements.add(accepted);
    if (!accepted && terminateOnRejectedAcknowledgement) {
      final NativeVoiceOwner owner = _owner!;
      final int revision = ++_revision;
      _lastTerminalLeaseId = leaseId;
      _lastTerminalRevision = revision;
      _stateController.add(NativeVoiceStateEvent(
        state: NativeVoiceCaptureState.error,
        leaseId: leaseId,
        owner: owner,
        revision: revision,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        errorCode: _errorCodeForStatus(status),
      ));
      _clearActiveCapture(advanceRevision: false);
    }
    return accepted;
  }

  void _clearActiveCapture({required bool advanceRevision}) {
    _endpoint.endSession();
    _owner = null;
    _leaseId = null;
    if (advanceRevision) _revision++;
  }

  String _errorCodeForStatus(int status) => switch (status) {
        NativePcmPacketEndpoint.consumerRejected => 'RECOGNITION_BACKLOG',
        NativePcmPacketEndpoint.consumerFailure => 'PCM_CONSUMER_FAILED',
        _ => 'INVALID_PCM_FRAME',
      };

  Future<void> dispose() async {
    final NativeVoiceOwner? owner = _owner;
    final int? leaseId = _leaseId;
    if (owner != null && leaseId != null) {
      await stop(owner: owner, leaseId: leaseId);
    }
    await _stateController.close();
  }

  Future<void> replay(
    Iterable<Uint8List> packets, {
    bool realTime = true,
  }) async {
    _timeline.reset();
    Duration targetElapsed = Duration.zero;
    for (final Uint8List packet in packets) {
      final bool accepted = await emit(packet);
      if (!accepted) return;
      if (!realTime) continue;

      targetElapsed += _packetDuration(packet.lengthInBytes);
      final Duration remaining = targetElapsed - _timeline.elapsed;
      if (remaining > Duration.zero) await _timeline.delay(remaining);
    }
  }

  static Duration _packetDuration(int bytes) => Duration(
        microseconds: bytes * 1000000 ~/ (16000 * 2),
      );

  /// Reads PCM16 mono/16 kHz WAV data in native 1024-byte packet sizes.
  static Future<List<Uint8List>> readMono16kWav(File file) async {
    return readMono16kWavBytes(await file.readAsBytes());
  }

  static List<Uint8List> readMono16kWavBytes(Uint8List bytes) {
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
            offset,
            (offset + packetBytes).clamp(0, pcm.lengthInBytes),
          ),
        ),
    ];
  }

}
