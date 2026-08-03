import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_replay_ownership.dart';

void main() {
  const VoiceReplayContext context = VoiceReplayContext(
    captureEpoch: 1,
    segmentId: 2,
    commandUtteranceId: 3,
    sourceScreen: WearScreenId.availabilityGroup,
    routeRevision: 4,
    grammarRevision: 5,
    freeTextEpoch: 6,
    listRevision: 7,
  );

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
}
