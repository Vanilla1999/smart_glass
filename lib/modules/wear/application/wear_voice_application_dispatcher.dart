import 'dart:async';

import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command_admission.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_delay_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_phrase_event.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_preview_event.dart';

typedef WearVoiceRevisionSnapshot = ({
  int captureEpoch,
  int routeRevision,
  int grammarRevision,
  int freeTextEpoch,
  int commandUtteranceId,
  int commandPartialRevision,
  int freeTextPartialRevision,
});

typedef WearVoiceLog = void Function(String message);

/// Production application boundary shared by WearModuleApp and replay tests.
///
/// It owns the policy that must not be copied into test listeners:
/// stale-context rejection, exactly-once admission, microphone pause/resume,
/// reconnect suppression and the final call into [WearFlowController].
class WearVoiceApplicationDispatcher {
  WearVoiceApplicationDispatcher({
    required WearFlowController flowController,
    required WearVoiceRevisionSnapshot Function() revisionSnapshotProvider,
    required bool Function() commandsEnabledProvider,
    required void Function(bool enabled) commandsEnabledSetter,
    required bool Function() acceptsCommandsProvider,
    WearVoiceEventAdmissionGate? admissionGate,
    void Function(WearVoiceCommandEvent event)? onCommandAccepted,
    void Function(WearVoicePreviewEvent event)? onPreviewUseful,
    WearVoiceLog? log,
  })  : _flow = flowController,
        _revisionSnapshotProvider = revisionSnapshotProvider,
        _commandsEnabledProvider = commandsEnabledProvider,
        _commandsEnabledSetter = commandsEnabledSetter,
        _acceptsCommandsProvider = acceptsCommandsProvider,
        _admissionGate = admissionGate ?? WearVoiceEventAdmissionGate(),
        _onCommandAccepted = onCommandAccepted,
        _onPreviewUseful = onPreviewUseful,
        _log = log ?? ((String message) => print(message));

  final WearFlowController _flow;
  final WearVoiceRevisionSnapshot Function() _revisionSnapshotProvider;
  final bool Function() _commandsEnabledProvider;
  final void Function(bool enabled) _commandsEnabledSetter;
  final bool Function() _acceptsCommandsProvider;
  final WearVoiceEventAdmissionGate _admissionGate;
  final void Function(WearVoiceCommandEvent event)? _onCommandAccepted;
  final void Function(WearVoicePreviewEvent event)? _onPreviewUseful;
  final WearVoiceLog _log;
  final Map<WearVoiceDelayKind, _VoiceDelayKey> _visibleDelayKeys =
      <WearVoiceDelayKind, _VoiceDelayKey>{};
  final Map<WearVoiceDelayKind, _VoiceDelayKey> _latestDelayKeys =
      <WearVoiceDelayKind, _VoiceDelayKey>{};

  WearVoiceEventAdmissionGate get admissionGate => _admissionGate;

  Future<WearVoiceAdmissionDecision> dispatchCommand(
    WearVoiceCommand command, {
    WearVoiceCommandEvent? event,
  }) async {
    if (event == null) {
      await _performCommand(command, event: null);
      return WearVoiceAdmissionDecision.accepted;
    }

    final WearVoiceAdmissionContext context = _context();
    final WearVoiceAdmissionDecision decision =
        await _admissionGate.runCommand(
      event,
      context: context,
      action: () => _performCommand(command, event: event),
    );
    if (decision != WearVoiceAdmissionDecision.accepted) {
      _log(
        '[WearVoiceApplicationDispatcher] suppress ${decision.name} '
        'voice command command=$command traceId=${event.traceId} '
        'sourceScreen=${event.sourceScreen} currentScreen=${context.screen} '
        'captureEpoch=${event.captureEpoch}/${context.captureEpoch} '
        'routeRevision=${event.routeRevision}/${context.routeRevision} '
        'grammarRevision=${event.grammarRevision}/${context.grammarRevision}',
      );
    }
    return decision;
  }

  Future<WearVoiceAdmissionDecision> dispatchPhrase(
    String phrase, {
    WearVoicePhraseEvent? event,
  }) async {
    if (event == null) {
      await _performPhrase(phrase);
      return WearVoiceAdmissionDecision.accepted;
    }

    final WearVoiceAdmissionContext context = _context();
    final WearVoiceAdmissionDecision decision =
        await _admissionGate.runPhrase(
      event,
      context: context,
      action: () => _performPhrase(phrase),
    );
    if (decision != WearVoiceAdmissionDecision.accepted) {
      _log(
        '[WearVoiceApplicationDispatcher] suppress ${decision.name} '
        'voice phrase phrase="$phrase" sourceScreen=${event.sourceScreen} '
        'currentScreen=${context.screen} '
        'captureEpoch=${event.captureEpoch}/${context.captureEpoch} '
        'routeRevision=${event.routeRevision}/${context.routeRevision} '
        'grammarRevision=${event.grammarRevision}/${context.grammarRevision} '
        'freeTextEpoch=${event.freeTextEpoch}/${context.freeTextEpoch} '
        'listRevision=${event.listRevision}/${context.listRevision}',
      );
    }
    return decision;
  }

  Future<bool> dispatchPreview(WearVoicePreviewEvent event) async {
    if (!_commandsEnabledProvider() || !_acceptsCommandsProvider()) return false;
    final WearVoiceRevisionSnapshot revisions = _revisionSnapshotProvider();
    final screen = _flow.state.screen;
    final VoiceDynamicItemsSnapshot items = _flow.dynamicVoiceItemsFor(screen);
    if (event.sourceScreen != screen ||
        event.captureEpoch != revisions.captureEpoch ||
        event.routeRevision != revisions.routeRevision ||
        event.grammarRevision != revisions.grammarRevision ||
        event.freeTextEpoch != revisions.freeTextEpoch ||
        event.commandUtteranceId != revisions.commandUtteranceId ||
        event.partialRevision !=
            (event.isCommandLane
                ? revisions.commandPartialRevision
                : revisions.freeTextPartialRevision) ||
        event.listRevision != items.revision) {
      _log('[WearVoiceApplicationDispatcher] suppress stale voice preview');
      return false;
    }

    VoiceDynamicItem? item;
    for (final VoiceDynamicItem candidate in items.items) {
      if (candidate.id == event.itemId) {
        item = candidate;
        break;
      }
    }
    if (item == null) return false;
    final bool useful = await _flow.handleVoicePartialPhrase(item.label);
    if (useful) _onPreviewUseful?.call(event);
    return useful;
  }

  Future<bool> dispatchDelay(WearVoiceDelayEvent event) async {
    final WearVoiceRevisionSnapshot revisions = _revisionSnapshotProvider();
    final screen = _flow.state.screen;
    final int currentListRevision =
        _flow.dynamicVoiceItemsFor(screen).revision;
    final bool contextCurrent = event.sourceScreen == screen &&
        event.captureEpoch == revisions.captureEpoch &&
        event.routeRevision == revisions.routeRevision &&
        event.grammarRevision == revisions.grammarRevision &&
        event.freeTextEpoch == revisions.freeTextEpoch &&
        (event.listRevision == 0 ||
            event.listRevision == currentListRevision);
    final _VoiceDelayKey key = (
      captureEpoch: event.captureEpoch,
      segmentId: event.segmentId,
      commandUtteranceId: event.commandUtteranceId,
    );
    if (event.visible) {
      if (!contextCurrent) return false;
      final _VoiceDelayKey? latest = _latestDelayKeys[event.kind];
      if (latest != null && _isOlderDelayKey(key, latest)) return false;
      _latestDelayKeys[event.kind] = key;
      _visibleDelayKeys[event.kind] = key;
    } else {
      if (_visibleDelayKeys[event.kind] != key) return false;
      _visibleDelayKeys.remove(event.kind);
    }
    await _flow.setRecognitionDelayVisible(
      event.sourceScreen,
      event.visible,
      event.previewText,
      kind: event.kind,
      statusText: event.statusText,
    );
    return true;
  }

  void resetAdmission() {
    _admissionGate.clear();
    _visibleDelayKeys.clear();
    _latestDelayKeys.clear();
  }

  bool _isOlderDelayKey(_VoiceDelayKey candidate, _VoiceDelayKey latest) {
    if (candidate.captureEpoch != latest.captureEpoch) {
      return candidate.captureEpoch < latest.captureEpoch;
    }
    if (candidate.segmentId != latest.segmentId) {
      return candidate.segmentId < latest.segmentId;
    }
    return candidate.commandUtteranceId < latest.commandUtteranceId;
  }

  WearVoiceAdmissionContext _context() {
    final WearVoiceRevisionSnapshot revisions = _revisionSnapshotProvider();
    final screen = _flow.state.screen;
    return (
      screen: screen,
      captureEpoch: revisions.captureEpoch,
      routeRevision: revisions.routeRevision,
      grammarRevision: revisions.grammarRevision,
      freeTextEpoch: revisions.freeTextEpoch,
      listRevision: _flow.dynamicVoiceItemsFor(screen).revision,
    );
  }

  Future<void> _performCommand(
    WearVoiceCommand command, {
    required WearVoiceCommandEvent? event,
  }) async {
    if (command == WearVoiceCommand.stopMicrophone) {
      _commandsEnabledSetter(false);
      return;
    }
    if (command == WearVoiceCommand.startMicrophone) {
      _commandsEnabledSetter(true);
      return;
    }
    if (!_commandsEnabledProvider()) {
      _log(
        '[WearVoiceApplicationDispatcher] suppress voice command: '
        'microphone paused command=$command',
      );
      return;
    }
    if (!_acceptsCommandsProvider()) {
      _log(
        '[WearVoiceApplicationDispatcher] suppress voice command during '
        'reconnect command=$command',
      );
      return;
    }

    final int startedAt = DateTime.now().millisecondsSinceEpoch;
    if (event != null) _onCommandAccepted?.call(event);
    _log(
      '[WearVoiceApplicationDispatcher] voice command received '
      'command=$command screen=${_flow.state.screen} at=$startedAt',
    );
    await _flow.handleVoiceCommand(command);
    final int finishedAt = DateTime.now().millisecondsSinceEpoch;
    _log(
      '[WearVoiceApplicationDispatcher] voice command handled '
      'command=$command screen=${_flow.state.screen} '
      'durationMs=${finishedAt - startedAt}',
    );
  }

  Future<void> _performPhrase(String phrase) async {
    if (!_commandsEnabledProvider()) {
      _log(
        '[WearVoiceApplicationDispatcher] suppress voice phrase: '
        'microphone paused',
      );
      return;
    }
    if (!_acceptsCommandsProvider()) {
      _log(
        '[WearVoiceApplicationDispatcher] suppress voice phrase during '
        'reconnect',
      );
      return;
    }

    final int startedAt = DateTime.now().millisecondsSinceEpoch;
    _log(
      '[WearVoiceApplicationDispatcher] voice phrase received '
      'phrase="$phrase" screen=${_flow.state.screen} at=$startedAt',
    );
    await _flow.handleVoicePhrase(phrase);
    final int finishedAt = DateTime.now().millisecondsSinceEpoch;
    _log(
      '[WearVoiceApplicationDispatcher] voice phrase handled '
      'phrase="$phrase" screen=${_flow.state.screen} '
      'durationMs=${finishedAt - startedAt}',
    );
  }
}

typedef _VoiceDelayKey = ({
  int captureEpoch,
  int segmentId,
  int commandUtteranceId,
});
