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
  });

  final NativeVoiceCaptureState state;
  final int? leaseId;
  final NativeVoiceOwner? owner;
  final int revision;
  final int timestampMs;
  final String? errorCode;
}

class NativePcmPacket {
  const NativePcmPacket({
    required this.leaseId,
    required this.sequence,
    required this.elapsedRealtimeNanos,
    required this.bytes,
  });

  final int leaseId;
  final int sequence;
  final int elapsedRealtimeNanos;
  final Uint8List bytes;
}

typedef NativePcmConsumer = FutureOr<bool> Function(NativePcmPacket packet);

class NativeVoiceCapture {
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

  NativePcmConsumer? _onPcm;
  int? _activeLeaseId;
  int? _activeRevision;
  NativeVoiceOwner? _activeOwner;
  int? _lastSequence;
  int? _lastTimestampNanos;
  bool _isStreaming = false;
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

  bool isRelevantStateEvent(NativeVoiceStateEvent event) {
    if (event.leaseId != null) return reconciledTermination(event);
    return _activeOwner != null &&
        (_activeRevision == null || event.revision >= _activeRevision!);
  }

  bool isOwnedBy(NativeVoiceOwner owner) => _activeOwner == owner;

  Future<Map<String, Object?>> getDiagnostics() async {
    final Map<Object?, Object?> result = await _methodChannel
            .invokeMapMethod<Object?, Object?>('getDiagnostics') ??
        const <Object?, Object?>{};
    return result.map(
      (Object? key, Object? value) => MapEntry(key.toString(), value),
    );
  }

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
      _onPcm = onPcm;
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
        _lastSequence = null;
        _lastTimestampNanos = null;
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
        _isStreaming = true;
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

  Future<ByteData> _onPacket(ByteData? packet) async {
    if (packet == null || packet.lengthInBytes < 32) {
      return _acknowledgement(2, 0, 0);
    }
    final ByteData header = ByteData.sublistView(packet, 0, 32);
    if (header.getUint32(0, Endian.big) != 1 ||
        header.getUint32(4, Endian.big) != 32) {
      return _acknowledgement(2, 0, 0);
    }
    final int leaseId = header.getInt64(8, Endian.big);
    final int sequence = header.getInt64(16, Endian.big);
    if (leaseId != _activeLeaseId) {
      return _acknowledgement(1, leaseId, sequence);
    }
    final int timestampNanos = header.getInt64(24, Endian.big);
    final Uint8List bytes = packet.buffer.asUint8List(
      packet.offsetInBytes + 32,
      packet.lengthInBytes - 32,
    );
    if (bytes.isEmpty ||
        bytes.lengthInBytes.isOdd ||
        sequence < 0 ||
        timestampNanos <= 0 ||
        (_lastSequence != null && sequence != _lastSequence! + 1) ||
        (_lastTimestampNanos != null &&
            timestampNanos <= _lastTimestampNanos!) ||
        _activeRevision == null ||
        !_isStreaming ||
        _onPcm == null) {
      return _acknowledgement(3, leaseId, sequence);
    }
    final NativePcmPacket pcm = NativePcmPacket(
      leaseId: leaseId,
      sequence: sequence,
      elapsedRealtimeNanos: timestampNanos,
      bytes: Uint8List.fromList(bytes),
    );
    try {
      final bool accepted = await _onPcm!(pcm);
      if (accepted && leaseId == _activeLeaseId) {
        _lastSequence = sequence;
        _lastTimestampNanos = timestampNanos;
      }
      return _acknowledgement(accepted ? 0 : 4, leaseId, sequence);
    } catch (_) {
      return _acknowledgement(4, leaseId, sequence);
    }
  }

  ByteData _acknowledgement(int status, int leaseId, int sequence) {
    final ByteData acknowledgement = ByteData(24)
      ..setUint32(0, 1, Endian.big)
      ..setUint32(4, status, Endian.big)
      ..setInt64(8, leaseId, Endian.big)
      ..setInt64(16, sequence, Endian.big);
    return acknowledgement;
  }

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
      _isStreaming = true;
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
    _onPcm = null;
    _activeLeaseId = null;
    _activeRevision = null;
    _activeOwner = null;
    _lastSequence = null;
    _lastTimestampNanos = null;
    _isStreaming = false;
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
