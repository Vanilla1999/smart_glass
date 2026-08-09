import 'dart:async';
import 'dart:collection';

import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_phrase_event.dart';

typedef WearVoiceAdmissionContext = ({
  WearScreenId screen,
  int captureEpoch,
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
  required int routeRevision,
  required int grammarRevision,
}) {
  return event.sourceScreen == screen &&
      event.captureEpoch == captureEpoch &&
      event.routeRevision == routeRevision &&
      event.grammarRevision == grammarRevision;
}

bool isCurrentWearVoicePhraseEvent(
  WearVoicePhraseEvent event, {
  required WearScreenId screen,
  required int captureEpoch,
  required int routeRevision,
  required int grammarRevision,
  required int freeTextEpoch,
  required int listRevision,
}) {
  return event.sourceScreen == screen &&
      event.captureEpoch == captureEpoch &&
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
  final LinkedHashMap<_WearVoiceContextKey, int> _highestCompletedUtterance =
      LinkedHashMap<_WearVoiceContextKey, int>();

  int get debugCompletedCount => _highestCompletedUtterance.length;
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
    _highestCompletedUtterance.clear();
  }

  Future<WearVoiceAdmissionDecision> _run(
    _WearVoiceActionKey key,
    FutureOr<void> Function() action,
  ) async {
    final _WearVoiceContextKey context = key.context;
    final int? highestCompleted = _highestCompletedUtterance[context];
    if ((highestCompleted != null &&
            key.commandUtteranceId <= highestCompleted) ||
        !_inFlight.add(key)) {
      return WearVoiceAdmissionDecision.duplicate;
    }
    try {
      await action();
      final int? previous = _highestCompletedUtterance.remove(context);
      while (_highestCompletedUtterance.length >= completedCapacity) {
        _highestCompletedUtterance.remove(
          _highestCompletedUtterance.keys.first,
        );
      }
      _highestCompletedUtterance[context] = previous == null ||
              key.commandUtteranceId > previous
          ? key.commandUtteranceId
          : previous;
      return WearVoiceAdmissionDecision.accepted;
    } finally {
      _inFlight.remove(key);
    }
  }
}

class _WearVoiceContextKey {
  const _WearVoiceContextKey({
    required this.captureEpoch,
    required this.sourceScreen,
    required this.routeRevision,
    required this.grammarRevision,
  });

  final int captureEpoch;
  final WearScreenId sourceScreen;
  final int routeRevision;
  final int grammarRevision;

  @override
  bool operator ==(Object other) {
    return other is _WearVoiceContextKey &&
        other.captureEpoch == captureEpoch &&
        other.sourceScreen == sourceScreen &&
        other.routeRevision == routeRevision &&
        other.grammarRevision == grammarRevision;
  }

  @override
  int get hashCode => Object.hash(
        captureEpoch,
        sourceScreen,
        routeRevision,
        grammarRevision,
      );
}

class _WearVoiceActionKey {
  const _WearVoiceActionKey({
    required this.captureEpoch,
    required this.commandUtteranceId,
    required this.sourceScreen,
    required this.routeRevision,
    required this.grammarRevision,
  });

  factory _WearVoiceActionKey.fromCommand(WearVoiceCommandEvent event) {
    return _WearVoiceActionKey(
      captureEpoch: event.captureEpoch,
      commandUtteranceId: event.commandUtteranceId,
      sourceScreen: event.sourceScreen,
      routeRevision: event.routeRevision,
      grammarRevision: event.grammarRevision,
    );
  }

  factory _WearVoiceActionKey.fromPhrase(WearVoicePhraseEvent event) {
    return _WearVoiceActionKey(
      captureEpoch: event.captureEpoch,
      commandUtteranceId: event.commandUtteranceId,
      sourceScreen: event.sourceScreen,
      routeRevision: event.routeRevision,
      grammarRevision: event.grammarRevision,
    );
  }

  _WearVoiceContextKey get context => _WearVoiceContextKey(
        captureEpoch: captureEpoch,
        sourceScreen: sourceScreen,
        routeRevision: routeRevision,
        grammarRevision: grammarRevision,
      );

  final int captureEpoch;
  final int commandUtteranceId;
  final WearScreenId sourceScreen;
  final int routeRevision;
  final int grammarRevision;

  @override
  bool operator ==(Object other) {
    return other is _WearVoiceActionKey &&
        other.captureEpoch == captureEpoch &&
        other.commandUtteranceId == commandUtteranceId &&
        other.sourceScreen == sourceScreen &&
        other.routeRevision == routeRevision &&
        other.grammarRevision == grammarRevision;
  }

  @override
  int get hashCode => Object.hash(
        captureEpoch,
        commandUtteranceId,
        sourceScreen,
        routeRevision,
        grammarRevision,
      );
}
