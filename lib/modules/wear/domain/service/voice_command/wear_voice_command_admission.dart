import 'dart:async';
import 'dart:collection';

import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_phrase_event.dart';

typedef WearVoiceAdmissionContext = ({
  WearScreenId screen,
  int captureEpoch,
  int recognitionContextId,
  int routeRevision,
  int grammarRevision,
  int freeTextEpoch,
  int listRevision,
});

enum WearVoiceAdmissionDecision {
  accepted,
  stale,
  duplicate,
}

bool isCurrentWearVoiceCommandEvent(
  WearVoiceCommandEvent event, {
  required WearScreenId screen,
  required int captureEpoch,
  required int recognitionContextId,
  required int routeRevision,
  required int grammarRevision,
}) {
  return event.sourceScreen == screen &&
      event.captureEpoch == captureEpoch &&
      event.recognitionContextId == recognitionContextId &&
      event.routeRevision == routeRevision &&
      event.grammarRevision == grammarRevision;
}

bool isCurrentWearVoicePhraseEvent(
  WearVoicePhraseEvent event, {
  required WearScreenId screen,
  required int captureEpoch,
  required int recognitionContextId,
  required int routeRevision,
  required int grammarRevision,
  required int freeTextEpoch,
  required int listRevision,
}) {
  return event.sourceScreen == screen &&
      event.captureEpoch == captureEpoch &&
      event.recognitionContextId == recognitionContextId &&
      event.routeRevision == routeRevision &&
      event.grammarRevision == grammarRevision &&
      event.freeTextEpoch == freeTextEpoch &&
      event.listRevision == listRevision;
}

/// Final admission boundary immediately before a voice event is allowed to
/// perform application work.
///
/// Recognition arbitration normally emits one intent, but application-level
/// deduplication is still required because a stream can be replayed, a late
/// free-text result can race a command result, or a listener can be rebound.
/// Command and phrase events deliberately share one utterance key so one
/// acoustic utterance cannot perform two business actions through two lanes.
class WearVoiceEventAdmissionGate {
  WearVoiceEventAdmissionGate({this.completedCapacity = 256}) {
    if (completedCapacity <= 0) {
      throw ArgumentError.value(
        completedCapacity,
        'completedCapacity',
        'must be greater than zero',
      );
    }
  }

  final int completedCapacity;
  final Set<_WearVoiceActionKey> _inFlight = <_WearVoiceActionKey>{};
  final Set<_WearVoiceUtteranceKey> _inFlightUtterances =
      <_WearVoiceUtteranceKey>{};
  final Set<_WearVoiceUtteranceKey> _claimedUtterances =
      <_WearVoiceUtteranceKey>{};
  final LinkedHashMap<_WearVoiceActionKey, bool> _completed =
      LinkedHashMap<_WearVoiceActionKey, bool>();
  final Map<_WearVoiceContextKey, int> _highestCompletedGeneration =
      <_WearVoiceContextKey, int>{};

  int get debugCompletedCount => _completed.length;
  int get debugInFlightCount => _inFlight.length;

  Future<WearVoiceAdmissionDecision> runCommand(
    WearVoiceCommandEvent event, {
    required WearVoiceAdmissionContext context,
    required FutureOr<void> Function() action,
  }) {
    if (!isCurrentWearVoiceCommandEvent(
      event,
      screen: context.screen,
      captureEpoch: context.captureEpoch,
      recognitionContextId: context.recognitionContextId,
      routeRevision: context.routeRevision,
      grammarRevision: context.grammarRevision,
    )) {
      return Future<WearVoiceAdmissionDecision>.value(
        WearVoiceAdmissionDecision.stale,
      );
    }
    return _run(_WearVoiceActionKey.fromCommand(event), action);
  }

  Future<WearVoiceAdmissionDecision> runPhrase(
    WearVoicePhraseEvent event, {
    required WearVoiceAdmissionContext context,
    required FutureOr<void> Function() action,
  }) {
    if (!isCurrentWearVoicePhraseEvent(
      event,
      screen: context.screen,
      captureEpoch: context.captureEpoch,
      recognitionContextId: context.recognitionContextId,
      routeRevision: context.routeRevision,
      grammarRevision: context.grammarRevision,
      freeTextEpoch: context.freeTextEpoch,
      listRevision: context.listRevision,
    )) {
      return Future<WearVoiceAdmissionDecision>.value(
        WearVoiceAdmissionDecision.stale,
      );
    }
    return _run(_WearVoiceActionKey.fromPhrase(event), action);
  }

  void clear() {
    _inFlight.clear();
    _inFlightUtterances.clear();
    _claimedUtterances.clear();
    _completed.clear();
    _highestCompletedGeneration.clear();
  }

  Future<WearVoiceAdmissionDecision> _run(
    _WearVoiceActionKey key,
    FutureOr<void> Function() action,
  ) async {
    final int? highest = _highestCompletedGeneration[key.context];
    if ((highest != null && key.commandUtteranceId <= highest) ||
        _completed.containsKey(key) ||
        _claimedUtterances.contains(key.utterance) ||
        !_inFlightUtterances.add(key.utterance)) {
      return WearVoiceAdmissionDecision.duplicate;
    }
    _inFlight.add(key);
    try {
      await action();
      while (_completed.length >= completedCapacity) {
        final _WearVoiceActionKey oldest = _completed.keys.first;
        _completed.remove(oldest);
        _claimedUtterances.remove(oldest.utterance);
      }
      _completed[key] = true;
      _claimedUtterances.add(key.utterance);
      final int previous = _highestCompletedGeneration[key.context] ?? 0;
      if (key.commandUtteranceId > previous) {
        _highestCompletedGeneration[key.context] = key.commandUtteranceId;
      }
      return WearVoiceAdmissionDecision.accepted;
    } finally {
      _inFlight.remove(key);
      _inFlightUtterances.remove(key.utterance);
    }
  }
}

class _WearVoiceContextKey {
  const _WearVoiceContextKey({
    required this.captureEpoch,
    required this.recognitionContextId,
    required this.sourceScreen,
    required this.routeRevision,
    required this.grammarRevision,
  });

  final int captureEpoch;
  final int recognitionContextId;
  final WearScreenId sourceScreen;
  final int routeRevision;
  final int grammarRevision;

  @override
  bool operator ==(Object other) {
    return other is _WearVoiceContextKey &&
        other.captureEpoch == captureEpoch &&
        other.recognitionContextId == recognitionContextId &&
        other.sourceScreen == sourceScreen &&
        other.routeRevision == routeRevision &&
        other.grammarRevision == grammarRevision;
  }

  @override
  int get hashCode => Object.hash(
        captureEpoch,
        recognitionContextId,
        sourceScreen,
        routeRevision,
        grammarRevision,
      );
}

class _WearVoiceActionKey {
  const _WearVoiceActionKey({
    required this.captureEpoch,
    required this.recognitionContextId,
    required this.commandUtteranceId,
    required this.commandType,
    required this.sourceScreen,
    required this.routeRevision,
    required this.grammarRevision,
  });

  factory _WearVoiceActionKey.fromCommand(WearVoiceCommandEvent event) {
    return _WearVoiceActionKey(
      captureEpoch: event.captureEpoch,
      recognitionContextId: event.recognitionContextId,
      commandUtteranceId: event.commandUtteranceId,
      commandType: event.command.name,
      sourceScreen: event.sourceScreen,
      routeRevision: event.routeRevision,
      grammarRevision: event.grammarRevision,
    );
  }

  factory _WearVoiceActionKey.fromPhrase(WearVoicePhraseEvent event) {
    return _WearVoiceActionKey(
      captureEpoch: event.captureEpoch,
      recognitionContextId: event.recognitionContextId,
      commandUtteranceId: event.commandUtteranceId,
      commandType: 'phrase',
      sourceScreen: event.sourceScreen,
      routeRevision: event.routeRevision,
      grammarRevision: event.grammarRevision,
    );
  }

  _WearVoiceContextKey get context => _WearVoiceContextKey(
        captureEpoch: captureEpoch,
        recognitionContextId: recognitionContextId,
        sourceScreen: sourceScreen,
        routeRevision: routeRevision,
        grammarRevision: grammarRevision,
      );

  final int captureEpoch;
  final int recognitionContextId;
  final int commandUtteranceId;
  final String commandType;
  final WearScreenId sourceScreen;
  final int routeRevision;
  final int grammarRevision;

  @override
  bool operator ==(Object other) {
    return other is _WearVoiceActionKey &&
        other.captureEpoch == captureEpoch &&
        other.recognitionContextId == recognitionContextId &&
        other.commandUtteranceId == commandUtteranceId &&
        other.commandType == commandType &&
        other.sourceScreen == sourceScreen &&
        other.routeRevision == routeRevision &&
        other.grammarRevision == grammarRevision;
  }

  @override
  int get hashCode => Object.hash(
        captureEpoch,
        recognitionContextId,
        commandUtteranceId,
        commandType,
        sourceScreen,
        routeRevision,
        grammarRevision,
      );

  _WearVoiceUtteranceKey get utterance => _WearVoiceUtteranceKey(
        captureEpoch: captureEpoch,
        recognitionContextId: recognitionContextId,
        commandUtteranceId: commandUtteranceId,
        sourceScreen: sourceScreen,
        routeRevision: routeRevision,
        grammarRevision: grammarRevision,
      );
}

class _WearVoiceUtteranceKey {
  const _WearVoiceUtteranceKey({
    required this.captureEpoch,
    required this.recognitionContextId,
    required this.commandUtteranceId,
    required this.sourceScreen,
    required this.routeRevision,
    required this.grammarRevision,
  });

  final int captureEpoch;
  final int recognitionContextId;
  final int commandUtteranceId;
  final WearScreenId sourceScreen;
  final int routeRevision;
  final int grammarRevision;

  @override
  bool operator ==(Object other) =>
      other is _WearVoiceUtteranceKey &&
      other.captureEpoch == captureEpoch &&
      other.recognitionContextId == recognitionContextId &&
      other.commandUtteranceId == commandUtteranceId &&
      other.sourceScreen == sourceScreen &&
      other.routeRevision == routeRevision &&
      other.grammarRevision == grammarRevision;

  @override
  int get hashCode => Object.hash(
        captureEpoch,
        recognitionContextId,
        commandUtteranceId,
        sourceScreen,
        routeRevision,
        grammarRevision,
      );
}
