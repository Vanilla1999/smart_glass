import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

enum NativeVoiceOwner { wearRecognition, legacyRecognition, voiceMemo }

enum NativeVoiceCaptureState {
  checkingCapabilities,
  unsupportedFirmware,
  activating,
  activated,
  binding,
  bound,
  initializing,
  initialized,
  starting,
  waitingForPcm,
  streaming,
  stopping,
  deinitializing,
  unbinding,
  cleanupComplete,
  idle,
  error,
  terminalAbandoned,
  disposed,
  unknown,
}

class NativeVoiceStateEvent {
  const NativeVoiceStateEvent({
    required this.state,
    required this.leaseId,
    required this.owner,
    required this.revision,
    required this.timestampMs,
    this.errorCode,
    this.errorDetails,
  });

  final NativeVoiceCaptureState state;
  final int? leaseId;
  final NativeVoiceOwner? owner;
  final int revision;
  final int timestampMs;
  final String? errorCode;
  final String? errorDetails;
}

class NativePcmPacket {
  const NativePcmPacket({
    required this.leaseId,
    required this.sequence,
    required this.elapsedRealtimeNanos,
    required this.capturedAtEpochMicros,
    required this.bytes,
  });

  final int leaseId;
  final int sequence;
  final int elapsedRealtimeNanos;
  final int capturedAtEpochMicros;
  final Uint8List bytes;
}

typedef NativePcmConsumer = FutureOr<bool> Function(NativePcmPacket packet);

class NativePcmPacketEndpoint {
  NativePcmPacketEndpoint({
    void Function(Object error, StackTrace stackTrace)? onConsumerError,
  }) : _onConsumerError = onConsumerError;

  static const int accepted = 0;
  static const int staleLease = 1;
  static const int malformedPacket = 2;
  static const int invalidPacket = 3;
  static const int consumerRejected = 4;
  static const int consumerFailure = 5;

  final void Function(Object error, StackTrace stackTrace)? _onConsumerError;
  _NativePcmSession? _session;
  int _generation = 0;

  int? get debugActiveRevision => _session?.revision;

  void beginSession({
    required int leaseId,
    required int revision,
    required NativePcmConsumer consumer,
  }) {
    _session = _NativePcmSession(
      generation: ++_generation,
      leaseId: leaseId,
      revision: revision,
      consumer: consumer,
    );
  }

  void markStreaming() {
    final _NativePcmSession? session = _session;
    if (session != null) session.isStreaming = true;
  }

  void endSession() {
    _generation++;
    _session = null;
  }

  Future<ByteData> handle(ByteData? packet) async {
    if (packet == null || packet.lengthInBytes < 40) {
      return acknowledgement(malformedPacket, 0, 0);
    }
    final ByteData header = ByteData.sublistView(packet, 0, 40);
    if (header.getUint32(0, Endian.big) != 2 ||
        header.getUint32(4, Endian.big) != 40) {
      return acknowledgement(malformedPacket, 0, 0);
    }
    final int leaseId = header.getInt64(8, Endian.big);
    final int sequence = header.getInt64(16, Endian.big);
    final _NativePcmSession? session = _session;
    if (session == null || leaseId != session.leaseId) {
      return acknowledgement(staleLease, leaseId, sequence);
    }
    final NativePcmPacket pcm = NativePcmPacket(
      leaseId: leaseId,
      sequence: sequence,
      elapsedRealtimeNanos: header.getInt64(24, Endian.big),
      capturedAtEpochMicros: header.getInt64(32, Endian.big),
      bytes: Uint8List.fromList(packet.buffer.asUint8List(
        packet.offsetInBytes + 40,
        packet.lengthInBytes - 40,
      )),
    );
    if (!session.canAccept(pcm)) {
      return acknowledgement(invalidPacket, leaseId, sequence);
    }
    session.pendingSequence = sequence;
    try {
      final bool admitted = await session.consumer(pcm);
      if (!identical(_session, session) || session.generation != _generation) {
        return acknowledgement(staleLease, leaseId, sequence);
      }
      session.pendingSequence = null;
      if (!admitted) {
        return acknowledgement(consumerRejected, leaseId, sequence);
      }
      session.lastSequence = sequence;
      session.lastTimestampNanos = pcm.elapsedRealtimeNanos;
      return acknowledgement(accepted, leaseId, sequence);
    } catch (error, stackTrace) {
      if (identical(_session, session) && session.pendingSequence == sequence) {
        session.pendingSequence = null;
      }
      _onConsumerError?.call(error, stackTrace);
      return acknowledgement(consumerFailure, leaseId, sequence);
    }
  }

  static ByteData acknowledgement(int status, int leaseId, int sequence) {
    return ByteData(24)
      ..setUint32(0, 1, Endian.big)
      ..setUint32(4, status, Endian.big)
      ..setInt64(8, leaseId, Endian.big)
      ..setInt64(16, sequence, Endian.big);
  }
}

class _NativePcmSession {
  _NativePcmSession({
    required this.generation,
    required this.leaseId,
    required this.revision,
    required this.consumer,
  });

  final int generation;
  final int leaseId;
  final int revision;
  final NativePcmConsumer consumer;
  bool isStreaming = false;
  int? pendingSequence;
  int? lastSequence;
  int? lastTimestampNanos;

  bool canAccept(NativePcmPacket packet) {
    return isStreaming &&
        pendingSequence == null &&
        packet.bytes.isNotEmpty &&
        packet.bytes.lengthInBytes.isEven &&
        packet.sequence == (lastSequence == null ? 0 : lastSequence! + 1) &&
        packet.elapsedRealtimeNanos > 0 &&
        packet.capturedAtEpochMicros > 0 &&
        (lastTimestampNanos == null ||
            packet.elapsedRealtimeNanos > lastTimestampNanos!);
  }
}

abstract interface class NativeVoiceStateSource {
  bool isOwnedBy(NativeVoiceOwner owner);
  bool isRelevantStateEvent(NativeVoiceStateEvent event);
}

/// Boundary used by the Dart voice pipeline to receive native PCM packets.
///
/// Production uses [NativeVoiceCapture]. Tests can replay recorded packets
/// without a UAC4 device while preserving the AudioStreamService contract.
abstract interface class NativeVoiceCapturePort {
  Future<Map<String, Object?>> getDiagnostics();
  Future<bool> requestPermission();
  Future<int> start({
    required NativeVoiceOwner owner,
    required NativePcmConsumer onPcm,
    bool recordDiagnosticWav = false,
    int? diagnosticCaptureTimestamp,
  });
  Future<void> stop({
    required NativeVoiceOwner owner,
    required int leaseId,
  });
}

class NativeVoiceCapture
    implements NativeVoiceCapturePort, NativeVoiceStateSource {
  NativeVoiceCapture._() {
    _pcmChannel.setMessageHandler(_onPacket);
    _stateSubscription = _eventChannel.receiveBroadcastStream().listen(
          _onStateEvent,
          onError: _stateController.addError,
        );
  }

  static final NativeVoiceCapture instance = NativeVoiceCapture._();
  static const MethodChannel _methodChannel =
      MethodChannel('ru.tander.smart_glasses/native_voice/control');
  static const BasicMessageChannel<ByteData> _pcmChannel =
      BasicMessageChannel<ByteData>(
    'ru.tander.smart_glasses/native_voice/pcm',
    BinaryCodec(),
  );
  static const EventChannel _eventChannel =
      EventChannel('ru.tander.smart_glasses/native_voice/events');

  int? _activeLeaseId;
  int? _activeRevision;
  NativeVoiceOwner? _activeOwner;
  final NativePcmPacketEndpoint _pcmEndpoint = NativePcmPacketEndpoint(
    onConsumerError: (Object error, StackTrace stackTrace) {
      print(
        '[NativeVoiceCapture] PCM consumer failed: '
        '$error\n$stackTrace',
      );
    },
  );
  int? _reconciledLeaseId;
  int? _reconciledRevision;
  int _operationGeneration = 0;
  Future<void> _controlOperation = Future<void>.value();
  Future<int>? _pendingStart;
  NativeVoiceOwner? _pendingStartOwner;
  late final StreamSubscription<dynamic> _stateSubscription;
  final StreamController<NativeVoiceStateEvent> _stateController =
      StreamController<NativeVoiceStateEvent>.broadcast();

  Stream<NativeVoiceStateEvent> get stateEvents => _stateController.stream;

  bool get isCapturing => _activeLeaseId != null;

  bool reconciledTermination(NativeVoiceStateEvent event) =>
      event.leaseId == _reconciledLeaseId &&
      event.revision == _reconciledRevision;

  @override
  bool isRelevantStateEvent(NativeVoiceStateEvent event) {
    if (event.leaseId != null) return reconciledTermination(event);
    return _activeOwner != null &&
        (_activeRevision == null || event.revision >= _activeRevision!);
  }

  @override
  bool isOwnedBy(NativeVoiceOwner owner) => _activeOwner == owner;

  @override
  Future<Map<String, Object?>> getDiagnostics() async {
    final Map<Object?, Object?> result = await _methodChannel
            .invokeMapMethod<Object?, Object?>('getDiagnostics') ??
        const <Object?, Object?>{};
    return result.map(
      (Object? key, Object? value) => MapEntry(key.toString(), value),
    );
  }

  @override
  Future<bool> requestPermission() async {
    final Map<Object?, Object?> capabilities = await _methodChannel
            .invokeMapMethod<Object?, Object?>('getCapabilities') ??
        const <Object?, Object?>{};
    if (capabilities['serviceAvailable'] != true) return false;
    if (capabilities['clientRecordAudioPermissionRequired'] != true ||
        capabilities['clientRecordAudioPermissionGranted'] == true) {
      return true;
    }
    if (capabilities['clientRecordAudioPermissionCanRequest'] != true) {
      return false;
    }
    return await _methodChannel.invokeMethod<bool>(
          'requestClientRecordAudioPermission',
        ) ??
        false;
  }

  @override
  Future<int> start({
    required NativeVoiceOwner owner,
    required NativePcmConsumer onPcm,
    bool recordDiagnosticWav = false,
    int? diagnosticCaptureTimestamp,
  }) {
    final Future<int>? pending = _pendingStart;
    if (pending != null) {
      if (_pendingStartOwner == owner) return pending;
      return Future<int>.error(
        StateError('Native voice capture start is already in flight.'),
      );
    }
    final int generation = ++_operationGeneration;
    late final Future<int> next;
    next = _serialize<int>(() async {
      if (_activeLeaseId != null) {
        throw StateError('Native voice capture is already active.');
      }
      _activeOwner = owner;
      try {
        await _methodChannel.invokeMethod<void>('prepare');
        if (generation != _operationGeneration) {
          throw const NativeVoiceStartCancelled();
        }
        final Map<Object?, Object?> result = await _methodChannel
                .invokeMapMethod<Object?, Object?>('start', <String, Object>{
              'owner': owner.name,
              'recordDiagnosticWav': recordDiagnosticWav,
              if (diagnosticCaptureTimestamp != null)
                'diagnosticCaptureTimestamp': diagnosticCaptureTimestamp,
            }) ??
            const <Object?, Object?>{};
        final int? leaseId = (result['leaseId'] as num?)?.toInt();
        final int? revision = (result['captureRevision'] as num?)?.toInt();
        if (leaseId == null || revision == null) {
          throw const FormatException(
            'Native voice capture returned no leaseId or captureRevision.',
          );
        }
        _activeLeaseId = leaseId;
        _activeRevision = revision;
        _pcmEndpoint.beginSession(
          leaseId: leaseId,
          revision: revision,
          consumer: onPcm,
        );
        try {
          await _methodChannel.invokeMethod<void>(
            'confirmStart',
            <String, Object>{
              'leaseId': leaseId,
              'captureRevision': revision,
            },
          );
        } catch (_) {
          try {
            await _stopNative(owner, leaseId);
          } finally {
            _clearCapture(leaseId: leaseId);
          }
          rethrow;
        }
        _pcmEndpoint.markStreaming();
        if (generation != _operationGeneration) {
          await _stopNative(owner, leaseId);
          _clearCapture(leaseId: leaseId, revision: revision);
          throw const NativeVoiceStartCancelled();
        }
        return leaseId;
      } catch (_) {
        if (_activeLeaseId == null) _clearCapture();
        rethrow;
      }
    }).whenComplete(() {
      if (identical(_pendingStart, next)) {
        _pendingStart = null;
        _pendingStartOwner = null;
      }
    });
    _pendingStart = next;
    _pendingStartOwner = owner;
    return next;
  }

  @override
  Future<void> stop({
    required NativeVoiceOwner owner,
    required int leaseId,
  }) async {
    _operationGeneration++;
    await _serialize<void>(() async {
      if (_activeLeaseId != leaseId) return;
      try {
        await _stopNative(owner, leaseId);
      } finally {
        _clearCapture(leaseId: leaseId);
      }
    });
  }

  Future<void> dispose() async {
    _operationGeneration++;
    await _serialize<void>(() async {
      _clearCapture();
      await _methodChannel.invokeMethod<void>('detach');
      await _stateSubscription.cancel();
      _pcmChannel.setMessageHandler(null);
      await _stateController.close();
    });
  }

  Future<ByteData> _onPacket(ByteData? packet) => _pcmEndpoint.handle(packet);

  static NativeVoiceStateEvent decodeStateEvent(Map<Object?, Object?> event) {
    final String stateName = event['state'] as String? ?? '';
    final NativeVoiceCaptureState state = switch (stateName) {
      'checkingCapabilities' => NativeVoiceCaptureState.checkingCapabilities,
      'unsupportedFirmware' => NativeVoiceCaptureState.unsupportedFirmware,
      'activating' => NativeVoiceCaptureState.activating,
      'activated' => NativeVoiceCaptureState.activated,
      'binding' => NativeVoiceCaptureState.binding,
      'bound' => NativeVoiceCaptureState.bound,
      'initializing' => NativeVoiceCaptureState.initializing,
      'initialized' || 'sspInitialized' => NativeVoiceCaptureState.initialized,
      'starting' => NativeVoiceCaptureState.starting,
      'waitingForPcm' => NativeVoiceCaptureState.waitingForPcm,
      'streaming' => NativeVoiceCaptureState.streaming,
      'stopping' => NativeVoiceCaptureState.stopping,
      'deinitializing' => NativeVoiceCaptureState.deinitializing,
      'unbinding' => NativeVoiceCaptureState.unbinding,
      'cleanupComplete' => NativeVoiceCaptureState.cleanupComplete,
      'idle' => NativeVoiceCaptureState.idle,
      'error' => NativeVoiceCaptureState.error,
      'terminalAbandoned' => NativeVoiceCaptureState.terminalAbandoned,
      'disposed' => NativeVoiceCaptureState.disposed,
      _ => NativeVoiceCaptureState.unknown,
    };
    final String? ownerName = event['owner'] as String?;
    return NativeVoiceStateEvent(
      state: state,
      leaseId: (event['leaseId'] as num?)?.toInt(),
      owner: switch (ownerName) {
        'wearRecognition' => NativeVoiceOwner.wearRecognition,
        'legacyRecognition' => NativeVoiceOwner.legacyRecognition,
        'voiceMemo' => NativeVoiceOwner.voiceMemo,
        _ => null,
      },
      revision: (event['revision'] as num?)?.toInt() ?? 0,
      timestampMs: (event['timestampMs'] as num?)?.toInt() ?? 0,
      errorCode: event['errorCode'] as String?,
      errorDetails: event['errorDetails'] as String?,
    );
  }

  void _onStateEvent(dynamic rawEvent) {
    if (rawEvent is! Map) {
      _stateController.addError(
        const FormatException('Native voice state event must be a map.'),
      );
      return;
    }
    final NativeVoiceStateEvent event =
        decodeStateEvent(rawEvent.cast<Object?, Object?>());
    final bool matchesCapture = _activeLeaseId != null &&
        event.leaseId == _activeLeaseId &&
        _activeRevision != null &&
        event.revision >= _activeRevision! &&
        (event.owner == null || event.owner == _activeOwner);
    if (matchesCapture && _terminatesLease(event.state)) {
      _reconciledLeaseId = _activeLeaseId;
      _reconciledRevision = event.revision;
      _clearCapture(leaseId: event.leaseId);
    } else if (matchesCapture &&
        event.state == NativeVoiceCaptureState.streaming) {
      _pcmEndpoint.markStreaming();
    }
    if (!_stateController.isClosed) _stateController.add(event);
  }

  bool _terminatesLease(NativeVoiceCaptureState state) => switch (state) {
        NativeVoiceCaptureState.initialized ||
        NativeVoiceCaptureState.idle ||
        NativeVoiceCaptureState.error ||
        NativeVoiceCaptureState.unsupportedFirmware ||
        NativeVoiceCaptureState.terminalAbandoned ||
        NativeVoiceCaptureState.disposed ||
        NativeVoiceCaptureState.unknown =>
          true,
        _ => false,
      };

  Future<void> _stopNative(NativeVoiceOwner owner, int leaseId) {
    return _methodChannel.invokeMethod<void>('stop', <String, Object>{
      'owner': owner.name,
      'leaseId': leaseId,
    });
  }

  void _clearCapture({int? leaseId, int? revision}) {
    if (leaseId != null && leaseId != _activeLeaseId) return;
    if (revision != null && revision != _activeRevision) return;
    _activeLeaseId = null;
    _activeRevision = null;
    _activeOwner = null;
    _pcmEndpoint.endSession();
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final Future<T> next = _controlOperation.then((_) => operation());
    _controlOperation = next.then<void>((_) {}, onError: (_, __) {});
    return next;
  }
}

class NativeVoiceStartCancelled implements Exception {
  const NativeVoiceStartCancelled();
}
