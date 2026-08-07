import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_delay_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_replay_feedback_controller.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_replay_ownership.dart';

void main() {
  group('WearVoiceReplayFeedbackController', () {
    test('fast successful replay does not flash processing status', () {
      final _ManualTimerFactory timers = _ManualTimerFactory();
      final List<WearVoiceDelayEvent> events = <WearVoiceDelayEvent>[];
      final WearVoiceReplayFeedbackController controller =
          WearVoiceReplayFeedbackController(
        onEvent: events.add,
        timerFactory: timers.call,
      );
      final VoiceReplayContext context = _context(segmentId: 1);

      controller.accept(_ownership(
        VoiceReplayOwnershipStatus.pending,
        context,
      ));
      controller.accept(_ownership(
        VoiceReplayOwnershipStatus.resolvedAsDynamicPhrase,
        context,
      ));
      timers.fireAll();

      expect(events, isEmpty);
      controller.dispose();
    });

    test('fast meaningful failure shows not recognized', () {
      final _ManualTimerFactory timers = _ManualTimerFactory();
      final List<WearVoiceDelayEvent> events = <WearVoiceDelayEvent>[];
      final WearVoiceReplayFeedbackController controller =
          WearVoiceReplayFeedbackController(
        onEvent: events.add,
        timerFactory: timers.call,
      );
      final VoiceReplayContext context = _context(segmentId: 2);

      controller.accept(_ownership(
        VoiceReplayOwnershipStatus.pending,
        context,
      ));
      controller.accept(
        _ownership(VoiceReplayOwnershipStatus.resolvedEmpty, context),
        meaningfulEvidence: true,
      );

      expect(events.single.visible, isTrue);
      expect(
        events.single.statusText,
        WearVoiceReplayFeedbackController.notRecognizedText,
      );

      timers.fire(const Duration(milliseconds: 1400));
      expect(events.last.visible, isFalse);
      controller.dispose();
    });

    test('fast noise-only failure stays silent', () {
      final _ManualTimerFactory timers = _ManualTimerFactory();
      final List<WearVoiceDelayEvent> events = <WearVoiceDelayEvent>[];
      final WearVoiceReplayFeedbackController controller =
          WearVoiceReplayFeedbackController(
        onEvent: events.add,
        timerFactory: timers.call,
      );
      final VoiceReplayContext context = _context(segmentId: 3);

      controller.accept(_ownership(
        VoiceReplayOwnershipStatus.pending,
        context,
      ));
      controller.accept(_ownership(
        VoiceReplayOwnershipStatus.resolvedEmpty,
        context,
      ));
      timers.fireAll();

      expect(events, isEmpty);
      controller.dispose();
    });

    test('long replay shows processing and clears it after success', () {
      final _ManualTimerFactory timers = _ManualTimerFactory();
      final List<WearVoiceDelayEvent> events = <WearVoiceDelayEvent>[];
      final WearVoiceReplayFeedbackController controller =
          WearVoiceReplayFeedbackController(
        onEvent: events.add,
        timerFactory: timers.call,
      );
      final VoiceReplayContext context = _context(segmentId: 4);

      controller.accept(_ownership(
        VoiceReplayOwnershipStatus.pending,
        context,
      ));
      timers.fire(const Duration(milliseconds: 180));

      expect(events.single.visible, isTrue);
      expect(
        events.single.statusText,
        WearVoiceReplayFeedbackController.recognizingText,
      );
      expect(events.single.kind, WearVoiceDelayKind.processing);

      controller.accept(_ownership(
        VoiceReplayOwnershipStatus.resolvedAsDynamicPhrase,
        context,
      ));

      expect(events.last.visible, isFalse);
      controller.dispose();
    });

    test('empty long replay shows failure and then restores content', () {
      final _ManualTimerFactory timers = _ManualTimerFactory();
      final List<WearVoiceDelayEvent> events = <WearVoiceDelayEvent>[];
      final WearVoiceReplayFeedbackController controller =
          WearVoiceReplayFeedbackController(
        onEvent: events.add,
        timerFactory: timers.call,
      );
      final VoiceReplayContext context = _context(segmentId: 3);

      controller.accept(_ownership(
        VoiceReplayOwnershipStatus.pending,
        context,
      ));
      timers.fire(const Duration(milliseconds: 180));
      controller.accept(_ownership(
        VoiceReplayOwnershipStatus.resolvedEmpty,
        context,
      ));

      expect(events.last.visible, isTrue);
      expect(
        events.last.statusText,
        WearVoiceReplayFeedbackController.notRecognizedText,
      );

      timers.fire(const Duration(milliseconds: 1400));
      expect(events.last.visible, isFalse);
      controller.dispose();
    });

    test('new speech immediately clears processing from an older segment', () {
      final _ManualTimerFactory timers = _ManualTimerFactory();
      final List<WearVoiceDelayEvent> events = <WearVoiceDelayEvent>[];
      final WearVoiceReplayFeedbackController controller =
          WearVoiceReplayFeedbackController(
        onEvent: events.add,
        timerFactory: timers.call,
      );
      final VoiceReplayContext context = _context(segmentId: 4);

      controller.accept(_ownership(
        VoiceReplayOwnershipStatus.pending,
        context,
      ));
      timers.fire(const Duration(milliseconds: 180));
      controller.onSegmentStarted(1, 5);

      expect(events.last.visible, isFalse);
      controller.dispose();
    });

    test('terminal event from an old replay cannot clear a newer one', () {
      final _ManualTimerFactory timers = _ManualTimerFactory();
      final List<WearVoiceDelayEvent> events = <WearVoiceDelayEvent>[];
      final WearVoiceReplayFeedbackController controller =
          WearVoiceReplayFeedbackController(
        onEvent: events.add,
        timerFactory: timers.call,
      );
      final VoiceReplayContext first = _context(segmentId: 6);
      final VoiceReplayContext second = _context(
        segmentId: 7,
        commandUtteranceId: 7,
      );

      controller.accept(_ownership(
        VoiceReplayOwnershipStatus.pending,
        first,
      ));
      timers.fire(const Duration(milliseconds: 180));
      controller.accept(_ownership(
        VoiceReplayOwnershipStatus.pending,
        second,
      ));
      timers.fire(const Duration(milliseconds: 180));
      final int eventCount = events.length;

      controller.accept(_ownership(
        VoiceReplayOwnershipStatus.resolvedEmpty,
        first,
      ));

      expect(events, hasLength(eventCount));
      expect(events.last.visible, isTrue);
      expect(events.last.segmentId, second.segmentId);
      expect(
        events.last.statusText,
        WearVoiceReplayFeedbackController.recognizingText,
      );
      controller.dispose();
    });
  });
}

VoiceReplayContext _context({
  required int segmentId,
  int commandUtteranceId = 1,
}) {
  return VoiceReplayContext(
    captureEpoch: 1,
    segmentId: segmentId,
    commandUtteranceId: commandUtteranceId,
    sourceScreen: WearScreenId.availabilityProduct,
    routeRevision: 2,
    grammarRevision: 3,
    freeTextEpoch: 4,
    listRevision: 5,
  );
}

VoiceReplayOwnership _ownership(
  VoiceReplayOwnershipStatus status,
  VoiceReplayContext context,
) {
  return VoiceReplayOwnership(status: status, context: context);
}

class _ManualTimerFactory {
  final List<_ManualTimer> _timers = <_ManualTimer>[];

  Timer call(Duration duration, void Function() callback) {
    final _ManualTimer timer = _ManualTimer(duration, callback);
    _timers.add(timer);
    return timer;
  }

  void fire(Duration duration) {
    _timers
        .firstWhere(
          (_ManualTimer timer) => timer.isActive && timer.duration == duration,
        )
        .fire();
  }

  void fireAll() {
    for (final _ManualTimer timer in List<_ManualTimer>.of(_timers)) {
      timer.fire();
    }
  }
}

class _ManualTimer implements Timer {
  _ManualTimer(this.duration, this._callback);

  final Duration duration;
  final void Function() _callback;
  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick++;
    _callback();
  }

  @override
  void cancel() {
    _active = false;
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}
