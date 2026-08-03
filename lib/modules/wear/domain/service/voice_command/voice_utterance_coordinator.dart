import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_list_matcher.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';

class VoiceDynamicItem {
  const VoiceDynamicItem({
    required this.id,
    required this.label,
    this.voiceAliases = const <String>[],
  });

  final String id;
  final String label;
  final List<String> voiceAliases;

  int get revisionHash => Object.hash(id, label, Object.hashAll(voiceAliases));
}

class VoiceDynamicItemsSnapshot {
  const VoiceDynamicItemsSnapshot({
    required this.revision,
    required this.items,
    this.excludedWords = const <String>{},
  });

  static const VoiceDynamicItemsSnapshot empty = VoiceDynamicItemsSnapshot(
    revision: 0,
    items: <VoiceDynamicItem>[],
  );

  final int revision;
  final List<VoiceDynamicItem> items;
  final Set<String> excludedWords;
}

class VoiceUtteranceKey {
  const VoiceUtteranceKey({
    required this.captureEpoch,
    required this.commandUtteranceId,
    required this.routeRevision,
    required this.grammarRevision,
    required this.freeTextEpoch,
    required this.sourceScreen,
  });

  final int captureEpoch;
  final int commandUtteranceId;
  final int routeRevision;
  final int grammarRevision;
  final int freeTextEpoch;
  final WearScreenId sourceScreen;

  @override
  bool operator ==(Object other) =>
      other is VoiceUtteranceKey &&
      other.captureEpoch == captureEpoch &&
      other.commandUtteranceId == commandUtteranceId &&
      other.routeRevision == routeRevision &&
      other.grammarRevision == grammarRevision &&
      other.freeTextEpoch == freeTextEpoch &&
      other.sourceScreen == sourceScreen;

  @override
  int get hashCode => Object.hash(
        captureEpoch,
        commandUtteranceId,
        routeRevision,
        grammarRevision,
        freeTextEpoch,
        sourceScreen,
      );
}

class VoiceDecisionContext {
  const VoiceDecisionContext({
    required this.key,
    required this.listRevision,
  });

  final VoiceUtteranceKey key;
  final int listRevision;
}

class CommandCandidate {
  const CommandCandidate({required this.command, required this.text});

  final WearVoiceCommand command;
  final String text;
}

class FreeTextCandidate {
  const FreeTextCandidate({
    required this.text,
    required this.matchType,
    this.itemId,
    this.isExactHint = false,
    this.isStableMatch = false,
  });

  final String text;
  final VoiceListMatchType matchType;
  final String? itemId;
  final bool isExactHint;
  final bool isStableMatch;
}

sealed class VoiceResolvedIntent {
  const VoiceResolvedIntent();
}

class FixedVoiceCommandIntent extends VoiceResolvedIntent {
  const FixedVoiceCommandIntent(this.command);

  final WearVoiceCommand command;
}

class DynamicVoiceItemIntent extends VoiceResolvedIntent {
  const DynamicVoiceItemIntent({
    required this.itemId,
    required this.spokenPhrase,
  });

  final String itemId;
  final String spokenPhrase;
}

class VoiceConflictIntent extends VoiceResolvedIntent {
  const VoiceConflictIntent({this.commandText, this.freeText});

  final String? commandText;
  final String? freeText;
}

enum VoiceDecisionKind {
  immediateCommand,
  command,
  dynamicItem,
  conflictRejected,
  ambiguousRejected,
  none,
  stale,
}

class VoiceDecision {
  const VoiceDecision(this.kind, {this.intent});

  final VoiceDecisionKind kind;
  final VoiceResolvedIntent? intent;
}

class VoiceUtteranceDecisionState {
  VoiceUtteranceDecisionState(this.context);

  final VoiceDecisionContext context;
  bool claimedByImmediateCommand = false;
  CommandCandidate? commandCandidate;
  FreeTextCandidate? freeTextCandidate;
  int? boundaryChunkId;
  bool commandFinalized = false;
  bool freeTextFinalized = false;
  bool replayFallbackStarted = false;
  bool decisionPublished = false;
}

class VoiceUtteranceCoordinator {
  final Map<VoiceUtteranceKey, VoiceUtteranceDecisionState> _states =
      <VoiceUtteranceKey, VoiceUtteranceDecisionState>{};

  VoiceUtteranceDecisionState stateFor(VoiceDecisionContext context) {
    final VoiceUtteranceDecisionState state = _states.putIfAbsent(
      context.key,
      () => VoiceUtteranceDecisionState(context),
    );
    while (_states.length > 128) {
      _states.remove(_states.keys.first);
    }
    return state;
  }

  VoiceDecision claimImmediate(
    VoiceDecisionContext context,
    WearVoiceCommand command,
  ) {
    final VoiceUtteranceDecisionState state = stateFor(context);
    if (state.decisionPublished) {
      return const VoiceDecision(VoiceDecisionKind.none);
    }
    state
      ..claimedByImmediateCommand = true
      ..decisionPublished = true;
    return VoiceDecision(
      VoiceDecisionKind.immediateCommand,
      intent: FixedVoiceCommandIntent(command),
    );
  }

  VoiceDecision decide({
    required VoiceDecisionContext context,
    required VoiceDecisionContext currentContext,
    CommandCandidate? command,
    FreeTextCandidate? freeText,
    required bool Function(String itemId) itemStillExists,
  }) {
    final VoiceUtteranceDecisionState state = stateFor(context);
    if (state.decisionPublished) {
      return const VoiceDecision(VoiceDecisionKind.none);
    }
    if (context.key != currentContext.key ||
        context.listRevision != currentContext.listRevision) {
      state.decisionPublished = true;
      return const VoiceDecision(VoiceDecisionKind.stale);
    }
    state
      ..commandCandidate = command
      ..freeTextCandidate = freeText
      ..commandFinalized = true
      ..freeTextFinalized = true
      ..decisionPublished = true;

    final String? dynamicItemId = freeText?.itemId;
    final bool uniqueDynamic =
        freeText?.matchType == VoiceListMatchType.unique &&
            dynamicItemId != null &&
            itemStillExists(dynamicItemId);
    if (uniqueDynamic && (freeText!.isExactHint || freeText.isStableMatch)) {
      return VoiceDecision(
        VoiceDecisionKind.dynamicItem,
        intent: DynamicVoiceItemIntent(
          itemId: dynamicItemId,
          spokenPhrase: freeText.text,
        ),
      );
    }
    if (command != null) {
      return VoiceDecision(
        VoiceDecisionKind.command,
        intent: FixedVoiceCommandIntent(command.command),
      );
    }
    if (uniqueDynamic) {
      return VoiceDecision(
        VoiceDecisionKind.dynamicItem,
        intent: DynamicVoiceItemIntent(
          itemId: dynamicItemId,
          spokenPhrase: freeText!.text,
        ),
      );
    }
    if (freeText?.matchType == VoiceListMatchType.ambiguous) {
      return const VoiceDecision(VoiceDecisionKind.ambiguousRejected);
    }
    return const VoiceDecision(VoiceDecisionKind.none);
  }

  void retainCurrentCapture(int captureEpoch) {
    _states.removeWhere(
      (VoiceUtteranceKey key, _) => key.captureEpoch != captureEpoch,
    );
  }

  void clear() => _states.clear();
}
