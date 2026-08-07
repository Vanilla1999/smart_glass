import 'dart:async';

import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_delay_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_replay_ownership.dart';

typedef WearVoiceReplayFeedbackTimerFactory = Timer Function(
  Duration duration,
  void Function() callback,
);

typedef WearVoiceReplayFeedbackSink = void Function(
  WearVoiceDelayEvent event,
);

class WearVoiceReplayFeedbackController {
  WearVoiceReplayFeedbackController({
    required WearVoiceReplayFeedbackSink onEvent,
    WearVoiceReplayFeedbackTimerFactory? timerFactory,
    this.recognizingDelay = const Duration(milliseconds: 180),
    this.failureDuration = const Duration(milliseconds: 1400),
  })  : _onEvent = onEvent,
        _timerFactory = timerFactory ?? Timer.new;

  static const String recognizingText = 'Распознаю...';
  static const String notRecognizedText = 'Не распознано';

  final WearVoiceReplayFeedbackSink _onEvent;
  final WearVoiceReplayFeedbackTimerFactory _timerFactory;
  final Duration recognizingDelay;
  final Duration failureDuration;

  Timer? _recognizingTimer;
  Timer? _failureTimer;
  VoiceReplayContext? _pendingContext;
  VoiceReplayContext? _visibleContext;
  int _generation = 0;

  void accept(
    VoiceReplayOwnership ownership, {
    bool meaningfulEvidence = false,
  }) {
    final VoiceReplayContext? context = ownership.context;
    if (context == null) {
      if (ownership.status == VoiceReplayOwnershipStatus.idle) {
        _clearActive();
      }
      return;
    }

    switch (ownership.status) {
      case VoiceReplayOwnershipStatus.idle:
        _clearActive();
        return;
      case VoiceReplayOwnershipStatus.pending:
        _begin(context);
        return;
      case VoiceReplayOwnershipStatus.resolvedAsCommand:
      case VoiceReplayOwnershipStatus.resolvedAsDynamicPhrase:
      case VoiceReplayOwnershipStatus.supersededByActionableUtterance:
      case VoiceReplayOwnershipStatus.cancelledByContextChange:
        _finish(context, showFailure: false);
        return;
      case VoiceReplayOwnershipStatus.resolvedEmpty:
      case VoiceReplayOwnershipStatus.timedOut:
      case VoiceReplayOwnershipStatus.failed:
        _finish(
          context,
          showFailure: true,
          showFastFailure: meaningfulEvidence,
        );
        return;
    }
  }

  void onSegmentStarted(int captureEpoch, int segmentId) {
    final VoiceReplayContext? active = _pendingContext ?? _visibleContext;
    if (active == null) return;
    final bool isNewer = captureEpoch > active.captureEpoch ||
        (captureEpoch == active.captureEpoch && segmentId > active.segmentId);
    if (isNewer) _clearActive();
  }

  void dispose() {
    _generation++;
    _recognizingTimer?.cancel();
    _failureTimer?.cancel();
    _recognizingTimer = null;
    _failureTimer = null;
    _pendingContext = null;
    _visibleContext = null;
  }

  void _begin(VoiceReplayContext context) {
    if (_pendingContext == context) return;
    _clearActive();
    _pendingContext = context;
    final int generation = ++_generation;
    _recognizingTimer = _timerFactory(recognizingDelay, () {
      if (generation != _generation || _pendingContext != context) return;
      _recognizingTimer = null;
      _visibleContext = context;
      _emit(context, visible: true, statusText: recognizingText);
    });
  }

  void _finish(
    VoiceReplayContext context, {
    required bool showFailure,
    bool showFastFailure = false,
  }) {
    if (_pendingContext != context && _visibleContext != context) return;
    _recognizingTimer?.cancel();
    _recognizingTimer = null;
    if (_pendingContext == context) _pendingContext = null;
    final int generation = ++_generation;

    if (showFailure && (_visibleContext == context || showFastFailure)) {
      _visibleContext = context;
      _emit(context, visible: true, statusText: notRecognizedText);
      _failureTimer?.cancel();
      _failureTimer = _timerFactory(failureDuration, () {
        if (generation != _generation || _visibleContext != context) return;
        _failureTimer = null;
        _visibleContext = null;
        _emit(context, visible: false);
      });
      return;
    }

    if (_visibleContext == context) {
      _visibleContext = null;
      _emit(context, visible: false);
    }
  }

  void _clearActive() {
    final VoiceReplayContext? visible = _visibleContext;
    _generation++;
    _recognizingTimer?.cancel();
    _failureTimer?.cancel();
    _recognizingTimer = null;
    _failureTimer = null;
    _pendingContext = null;
    _visibleContext = null;
    if (visible != null) _emit(visible, visible: false);
  }

  void _emit(
    VoiceReplayContext context, {
    required bool visible,
    String? statusText,
  }) {
    _onEvent(WearVoiceDelayEvent(
      visible: visible,
      captureEpoch: context.captureEpoch,
      segmentId: context.segmentId,
      sourceScreen: context.sourceScreen,
      routeRevision: context.routeRevision,
      grammarRevision: context.grammarRevision,
      freeTextEpoch: context.freeTextEpoch,
      commandUtteranceId: context.commandUtteranceId,
      listRevision: context.listRevision,
      kind: WearVoiceDelayKind.processing,
      statusText: statusText,
    ));
  }
}
