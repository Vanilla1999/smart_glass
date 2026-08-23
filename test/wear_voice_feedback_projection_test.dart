import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_glasses_output.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_navigation_entry.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/application/wear_voice_application_dispatcher.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_replay_feedback_controller.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_replay_ownership.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

import 'support/wear_runtime_test_helper.dart';

void main() {
  test('replay feedback reaches the glasses payload and clears in order',
      () async {
    final _RecordingGlassesOutput glasses = _RecordingGlassesOutput();
    final WearFlowController flow = createWearFlowController(
      authority: await createActiveWearRuntimeAuthority(),
      glassesOutput: glasses,
      navigationOutput: _NoopNavigationOutput(),
    );
    addTearDown(flow.dispose);
    await flow.requestNavigation(WearScreenId.menu);

    var commandsEnabled = true;
    final WearVoiceApplicationDispatcher dispatcher =
        WearVoiceApplicationDispatcher(
      flowController: flow,
      revisionSnapshotProvider: () => (
        captureEpoch: 1,
        recognitionContextId: 1,
        routeRevision: 1,
        grammarRevision: 1,
        freeTextEpoch: 1,
        commandUtteranceId: 9,
        commandPartialRevision: 0,
        freeTextPartialRevision: 0,
      ),
      commandsEnabledProvider: () => commandsEnabled,
      commandsEnabledSetter: (bool enabled) => commandsEnabled = enabled,
      acceptsCommandsProvider: () => true,
      log: (_) {},
    );
    final _ManualTimers timers = _ManualTimers();
    final List<Future<bool>> renders = <Future<bool>>[];
    final WearVoiceReplayFeedbackController feedback =
        WearVoiceReplayFeedbackController(
      timerFactory: timers.schedule,
      onEvent: (event) => renders.add(dispatcher.dispatchDelay(event)),
    );
    addTearDown(feedback.dispose);

    const VoiceReplayContext context = VoiceReplayContext(
      captureEpoch: 1,
      segmentId: 8,
      speechTurnId: 8,
      commandUtteranceId: 9,
      sourceScreen: WearScreenId.menu,
      routeRevision: 1,
      grammarRevision: 1,
      freeTextEpoch: 1,
      listRevision: 0,
    );

    feedback.accept(const VoiceReplayOwnership(
      status: VoiceReplayOwnershipStatus.pending,
      context: context,
    ));
    timers.elapse(const Duration(milliseconds: 180));
    await _drain(renders);
    expect(glasses.payloads.last.statusText, 'Распознаю...');

    feedback.accept(const VoiceReplayOwnership(
      status: VoiceReplayOwnershipStatus.resolvedEmpty,
      context: context,
    ));
    await _drain(renders);
    expect(glasses.payloads.last.statusText, 'Не распознано');

    timers.elapse(const Duration(milliseconds: 1400));
    await _drain(renders);
    expect(glasses.payloads.last.statusText, isNull);
    expect(
      glasses.payloads.map((WearGlassesPayload payload) => payload.statusText),
      containsAllInOrder(<String?>[
        'Распознаю...',
        'Не распознано',
        null,
      ]),
    );
  });
}

Future<void> _drain(List<Future<bool>> renders) async {
  if (renders.isEmpty) return;
  await Future.wait<bool>(List<Future<bool>>.of(renders));
  renders.clear();
}

class _ManualTimers {
  Duration _elapsed = Duration.zero;
  final List<_ManualTimer> _timers = <_ManualTimer>[];

  Timer schedule(Duration duration, void Function() callback) {
    final _ManualTimer timer = _ManualTimer(
      deadline: _elapsed + duration,
      callback: callback,
    );
    _timers.add(timer);
    return timer;
  }

  void elapse(Duration duration) {
    _elapsed += duration;
    for (final _ManualTimer timer in List<_ManualTimer>.of(_timers)) {
      if (timer.isActive && timer.deadline <= _elapsed) timer.fire();
    }
  }
}

class _ManualTimer implements Timer {
  _ManualTimer({required this.deadline, required this.callback});

  final Duration deadline;
  final void Function() callback;
  bool _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    callback();
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => _active ? 0 : 1;

  @override
  void cancel() => _active = false;
}

class _RecordingGlassesOutput implements WearGlassesOutput {
  final List<WearGlassesPayload> payloads = <WearGlassesPayload>[];

  @override
  Future<void> send(WearGlassesPayload payload) async {
    payloads.add(payload);
  }
}

class _NoopNavigationOutput implements WearNavigationOutput {
  @override
  Future<void> back() async {}

  @override
  Future<void> goTo(WearScreenId screen, {Object? extra}) async {}

  @override
  Future<void> home() async {}

  @override
  Future<void> replace(WearScreenId screen, {Object? extra}) async {}

  @override
  Future<void> synchronize(List<WearNavigationEntry> history) async {}
}
