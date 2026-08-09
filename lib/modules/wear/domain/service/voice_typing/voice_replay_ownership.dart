import 'dart:async';

import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';

enum VoiceReplayOwnershipStatus {
  idle,
  pending,
  resolvedAsCommand,
  resolvedAsDynamicPhrase,
  resolvedEmpty,
  supersededByActionableUtterance,
  cancelledByContextChange,
  timedOut,
  failed,
}

enum VoiceReplayContextCancellation {
  sessionStopped,
  captureChanged,
  freeTextChanged,
  screenChanged,
  routeChanged,
  grammarChanged,
  dynamicItemsChanged,
  newerSegmentStarted,
}

class VoiceReplayContext {
  const VoiceReplayContext({
    required this.captureEpoch,
    required this.segmentId,
    required this.speechTurnId,
    required this.commandUtteranceId,
    required this.sourceScreen,
    required this.routeRevision,
    required this.grammarRevision,
    required this.freeTextEpoch,
    required this.listRevision,
  });

  final int captureEpoch;

  /// Diagnostic VAD segment only. Max-duration rollover can change this value
  /// while the semantic speech turn and replay ownership stay unchanged.
  final int segmentId;
  final int speechTurnId;

  /// Until decoderGeneration is introduced explicitly, commandUtteranceId is
  /// the decoder-generation component of replay identity.
  final int commandUtteranceId;
  final WearScreenId sourceScreen;
  final int routeRevision;
  final int grammarRevision;
  final int freeTextEpoch;
  final int listRevision;

  String get traceId => '$captureEpoch:$speechTurnId:$commandUtteranceId';

  @override
  bool operator ==(Object other) =>
      other is VoiceReplayContext &&
      other.captureEpoch == captureEpoch &&
      other.speechTurnId == speechTurnId &&
      other.commandUtteranceId == commandUtteranceId &&
      other.sourceScreen == sourceScreen &&
      other.routeRevision == routeRevision &&
      other.grammarRevision == grammarRevision &&
      other.freeTextEpoch == freeTextEpoch &&
      other.listRevision == listRevision;

  @override
  int get hashCode => Object.hash(
        captureEpoch,
        speechTurnId,
        commandUtteranceId,
        sourceScreen,
        routeRevision,
        grammarRevision,
        freeTextEpoch,
        listRevision,
      );

  @override
  String toString() => 'VoiceReplayContext('
      'traceId=$traceId, segmentId=$segmentId, '
      'screen=${sourceScreen.name}, routeRevision=$routeRevision, '
      'grammarRevision=$grammarRevision, freeTextEpoch=$freeTextEpoch, '
      'listRevision=$listRevision)';
}

class VoiceReplayOwnership {
  const VoiceReplayOwnership({
    required this.status,
    this.context,
    this.cancellation,
    this.supersededByUtteranceId,
    this.failure,
  });

  static const VoiceReplayOwnership idle = VoiceReplayOwnership(
    status: VoiceReplayOwnershipStatus.idle,
  );

  final VoiceReplayOwnershipStatus status;
  final VoiceReplayContext? context;
  final VoiceReplayContextCancellation? cancellation;
  final int? supersededByUtteranceId;
  final Object? failure;

  bool get isTerminal => switch (status) {
        VoiceReplayOwnershipStatus.idle ||
        VoiceReplayOwnershipStatus.pending =>
          false,
        _ => true,
      };
}

class VoiceReplayOwnershipStateMachine {
  VoiceReplayOwnership _current = VoiceReplayOwnership.idle;
  final Map<VoiceReplayContext, VoiceReplayOwnership> _states =
      <VoiceReplayContext, VoiceReplayOwnership>{};
  final StreamController<VoiceReplayOwnership> _transitions =
      StreamController<VoiceReplayOwnership>.broadcast(sync: true);

  VoiceReplayOwnership get current => _current;
  Stream<VoiceReplayOwnership> get transitions => _transitions.stream;

  VoiceReplayOwnership begin(VoiceReplayContext context) {
    final VoiceReplayOwnership? existing = _states[context];
    if (existing != null) {
      // A technical VAD rollover may present the same semantic replay with a
      // different diagnostic segmentId. Do not reopen or duplicate ownership.
      return existing;
    }
    final VoiceReplayOwnership state = VoiceReplayOwnership(
      status: VoiceReplayOwnershipStatus.pending,
      context: context,
    );
    _states[context] = state;
    _publish(state);
    return state;
  }

  VoiceReplayOwnership resolve(
    VoiceReplayContext context,
    VoiceReplayOwnershipStatus status, {
    VoiceReplayContextCancellation? cancellation,
    int? supersededByUtteranceId,
    Object? failure,
  }) {
    if (status == VoiceReplayOwnershipStatus.idle ||
        status == VoiceReplayOwnershipStatus.pending) {
      throw ArgumentError.value(status, 'status', 'must be terminal');
    }
    final VoiceReplayOwnership? previous = _states[context];
    if (previous == null) {
      throw StateError('Replay was not started for context $context');
    }
    if (previous.isTerminal) return previous;
    final VoiceReplayOwnership state = VoiceReplayOwnership(
      status: status,
      // Preserve the context used by begin(), including the first diagnostic
      // segmentId, even if resolve() arrived through a rollover-equivalent key.
      context: previous.context ?? context,
      cancellation: cancellation,
      supersededByUtteranceId: supersededByUtteranceId,
      failure: failure,
    );
    _states[context] = state;
    _publish(state);
    while (_states.length > 128) {
      _states.remove(_states.keys.first);
    }
    return state;
  }

  VoiceReplayOwnership? stateFor(VoiceReplayContext context) =>
      _states[context];

  void _publish(VoiceReplayOwnership state) {
    _current = state;
    if (!_transitions.isClosed) _transitions.add(state);
  }

  Future<void> dispose() => _transitions.close();
}
