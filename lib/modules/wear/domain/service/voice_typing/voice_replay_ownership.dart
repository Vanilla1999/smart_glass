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
  recognitionContextChanged,
  freeTextChanged,
  screenChanged,
  routeChanged,
  grammarChanged,
  dynamicItemsChanged,
  newerSegmentStarted,
}

class VoiceWorkIdentity {
  const VoiceWorkIdentity({
    required this.captureEpoch,
    this.recognitionContextId = 1,
    required this.speechTurnId,
    required this.decoderGeneration,
    required this.sourceScreen,
    required this.routeRevision,
    required this.grammarRevision,
    required this.freeTextConfigurationRevision,
    required this.listRevision,
  });

  final int captureEpoch;
  final int recognitionContextId;

  final int speechTurnId;
  final int decoderGeneration;
  final WearScreenId sourceScreen;
  final int routeRevision;
  final int grammarRevision;
  final int freeTextConfigurationRevision;
  final int listRevision;

  int get commandUtteranceId => decoderGeneration;
  int get freeTextEpoch => freeTextConfigurationRevision;
  String get traceId => '$captureEpoch:$speechTurnId:$decoderGeneration';

  @override
  bool operator ==(Object other) =>
      other is VoiceWorkIdentity &&
      other.captureEpoch == captureEpoch &&
      other.recognitionContextId == recognitionContextId &&
      other.speechTurnId == speechTurnId &&
      other.decoderGeneration == decoderGeneration &&
      other.sourceScreen == sourceScreen &&
      other.routeRevision == routeRevision &&
      other.grammarRevision == grammarRevision &&
      other.freeTextConfigurationRevision == freeTextConfigurationRevision &&
      other.listRevision == listRevision;

  @override
  int get hashCode => Object.hash(
        captureEpoch,
        recognitionContextId,
        speechTurnId,
        decoderGeneration,
        sourceScreen,
        routeRevision,
        grammarRevision,
        freeTextConfigurationRevision,
        listRevision,
      );
}

class VoiceReplayContext {
  const VoiceReplayContext({
    required this.captureEpoch,
    this.recognitionContextId = 1,
    required this.segmentId,
    required this.speechTurnId,
    required int commandUtteranceId,
    required this.sourceScreen,
    required this.routeRevision,
    required this.grammarRevision,
    required int freeTextEpoch,
    required this.listRevision,
  })  : decoderGeneration = commandUtteranceId,
        freeTextConfigurationRevision = freeTextEpoch;

  VoiceReplayContext.withIdentity({
    required VoiceWorkIdentity identity,
    required this.segmentId,
  })  : captureEpoch = identity.captureEpoch,
        recognitionContextId = identity.recognitionContextId,
        speechTurnId = identity.speechTurnId,
        decoderGeneration = identity.decoderGeneration,
        sourceScreen = identity.sourceScreen,
        routeRevision = identity.routeRevision,
        grammarRevision = identity.grammarRevision,
        freeTextConfigurationRevision = identity.freeTextConfigurationRevision,
        listRevision = identity.listRevision;

  final int captureEpoch;
  final int recognitionContextId;

  /// Diagnostic VAD segment only. Max-duration rollover can change this value
  /// while the semantic speech turn and replay ownership stay unchanged.
  final int segmentId;
  final int speechTurnId;
  final int decoderGeneration;
  final WearScreenId sourceScreen;
  final int routeRevision;
  final int grammarRevision;
  final int freeTextConfigurationRevision;
  final int listRevision;

  VoiceWorkIdentity get identity => VoiceWorkIdentity(
        captureEpoch: captureEpoch,
        recognitionContextId: recognitionContextId,
        speechTurnId: speechTurnId,
        decoderGeneration: decoderGeneration,
        sourceScreen: sourceScreen,
        routeRevision: routeRevision,
        grammarRevision: grammarRevision,
        freeTextConfigurationRevision: freeTextConfigurationRevision,
        listRevision: listRevision,
      );

  int get commandUtteranceId => decoderGeneration;
  int get freeTextEpoch => freeTextConfigurationRevision;
  String get traceId => identity.traceId;

  @override
  bool operator ==(Object other) =>
      other is VoiceReplayContext && other.identity == identity;

  @override
  int get hashCode => identity.hashCode;

  @override
  String toString() => 'VoiceReplayContext('
      'traceId=$traceId, segmentId=$segmentId, '
      'contextId=$recognitionContextId, '
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
