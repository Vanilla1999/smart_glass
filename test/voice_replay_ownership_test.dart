import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_replay_ownership.dart';

void main() {
  const VoiceReplayContext context = VoiceReplayContext(
    captureEpoch: 1,
    segmentId: 2,
    speechTurnId: 11,
    commandUtteranceId: 3,
    sourceScreen: WearScreenId.availabilityGroup,
    routeRevision: 4,
    grammarRevision: 5,
    freeTextEpoch: 6,
    listRevision: 7,
  );

  test('work identity keeps recognition context ownership immutable', () {
    const VoiceWorkIdentity first = VoiceWorkIdentity(
      captureEpoch: 1,
      recognitionContextId: 2,
      speechTurnId: 3,
      decoderGeneration: 4,
      sourceScreen: WearScreenId.menu,
      routeRevision: 1,
      grammarRevision: 1,
      freeTextConfigurationRevision: 0,
      listRevision: 0,
    );
    const VoiceWorkIdentity nextContext = VoiceWorkIdentity(
      captureEpoch: 1,
      recognitionContextId: 3,
      speechTurnId: 3,
      decoderGeneration: 4,
      sourceScreen: WearScreenId.menu,
      routeRevision: 1,
      grammarRevision: 1,
      freeTextConfigurationRevision: 0,
      listRevision: 0,
    );

    expect(first, isNot(nextContext));
    expect(first.recognitionContextId, 2);
  });

  test('publishes pending then one terminal ownership transition', () async {
    final VoiceReplayOwnershipStateMachine machine =
        VoiceReplayOwnershipStateMachine();
    addTearDown(machine.dispose);
    final List<VoiceReplayOwnership> transitions = <VoiceReplayOwnership>[];
    machine.transitions.listen(transitions.add);

    machine.begin(context);
    final VoiceReplayOwnership resolved = machine.resolve(
      context,
      VoiceReplayOwnershipStatus.resolvedAsDynamicPhrase,
    );
    final VoiceReplayOwnership duplicate = machine.resolve(
      context,
      VoiceReplayOwnershipStatus.failed,
      failure: StateError('late failure'),
    );

    expect(
      transitions.map((state) => state.status),
      <VoiceReplayOwnershipStatus>[
        VoiceReplayOwnershipStatus.pending,
        VoiceReplayOwnershipStatus.resolvedAsDynamicPhrase,
      ],
    );
    expect(resolved.isTerminal, isTrue);
    expect(duplicate, same(resolved));
  });

  test('retains typed supersede and context cancellation details', () async {
    final VoiceReplayOwnershipStateMachine machine =
        VoiceReplayOwnershipStateMachine();
    addTearDown(machine.dispose);

    machine.begin(context);
    final VoiceReplayOwnership superseded = machine.resolve(
      context,
      VoiceReplayOwnershipStatus.supersededByActionableUtterance,
      supersededByUtteranceId: 4,
    );

    expect(superseded.supersededByUtteranceId, 4);
    expect(superseded.isTerminal, isTrue);

    const VoiceReplayContext next = VoiceReplayContext(
      captureEpoch: 1,
      segmentId: 3,
      speechTurnId: 12,
      commandUtteranceId: 4,
      sourceScreen: WearScreenId.availabilityProduct,
      routeRevision: 5,
      grammarRevision: 6,
      freeTextEpoch: 7,
      listRevision: 8,
    );
    machine.begin(next);
    final VoiceReplayOwnership cancelled = machine.resolve(
      next,
      VoiceReplayOwnershipStatus.cancelledByContextChange,
      cancellation: VoiceReplayContextCancellation.dynamicItemsChanged,
    );

    expect(
      cancelled.cancellation,
      VoiceReplayContextCancellation.dynamicItemsChanged,
    );
  });

  test('rejects terminal transition without pending replay', () async {
    final VoiceReplayOwnershipStateMachine machine =
        VoiceReplayOwnershipStateMachine();
    addTearDown(machine.dispose);

    expect(
      () => machine.resolve(context, VoiceReplayOwnershipStatus.timedOut),
      throwsStateError,
    );
  });

  test('technical segment rollover keeps one semantic replay owner', () async {
    final VoiceReplayOwnershipStateMachine machine =
        VoiceReplayOwnershipStateMachine();
    addTearDown(machine.dispose);
    final List<VoiceReplayOwnership> transitions = <VoiceReplayOwnership>[];
    machine.transitions.listen(transitions.add);

    const VoiceReplayContext rollover = VoiceReplayContext(
      captureEpoch: 1,
      segmentId: 99,
      speechTurnId: 11,
      commandUtteranceId: 3,
      sourceScreen: WearScreenId.availabilityGroup,
      routeRevision: 4,
      grammarRevision: 5,
      freeTextEpoch: 6,
      listRevision: 7,
    );

    expect(rollover, context);
    expect(rollover.hashCode, context.hashCode);
    expect(rollover.traceId, '1:1:3');

    final VoiceReplayOwnership first = machine.begin(context);
    final VoiceReplayOwnership duplicate = machine.begin(rollover);
    final VoiceReplayOwnership resolved = machine.resolve(
      rollover,
      VoiceReplayOwnershipStatus.resolvedEmpty,
    );

    expect(duplicate, same(first));
    expect(resolved.context, context);
    expect(machine.stateFor(context), same(resolved));
    expect(machine.stateFor(rollover), same(resolved));
    expect(
      transitions.map((state) => state.status),
      <VoiceReplayOwnershipStatus>[
        VoiceReplayOwnershipStatus.pending,
        VoiceReplayOwnershipStatus.resolvedEmpty,
      ],
    );
  });

  test('speech turn remains diagnostic outside replay identity', () {
    const VoiceReplayContext nextTurn = VoiceReplayContext(
      captureEpoch: 1,
      segmentId: 2,
      speechTurnId: 12,
      commandUtteranceId: 3,
      sourceScreen: WearScreenId.availabilityGroup,
      routeRevision: 4,
      grammarRevision: 5,
      freeTextEpoch: 6,
      listRevision: 7,
    );

    expect(nextTurn, context);
    expect(nextTurn.traceId, '1:1:3');
  });

  test('voice work identity exposes compatibility revisions', () {
    expect(context.identity.decoderGeneration, 3);
    expect(context.identity.commandUtteranceId, 3);
    expect(context.identity.freeTextConfigurationRevision, 6);
    expect(context.identity.freeTextEpoch, 6);
    expect(context.decoderGeneration, 3);
    expect(context.freeTextConfigurationRevision, 6);
  });
}
