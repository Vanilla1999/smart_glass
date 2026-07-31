import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_list_matcher.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';

void main() {
  VoiceDecisionContext context({
    int capture = 1,
    int utterance = 1,
    int route = 1,
    int grammar = 1,
    int freeText = 1,
    int list = 1,
  }) =>
      VoiceDecisionContext(
        key: VoiceUtteranceKey(
          captureEpoch: capture,
          commandUtteranceId: utterance,
          routeRevision: route,
          grammarRevision: grammar,
          freeTextEpoch: freeText,
          sourceScreen: WearScreenId.printerSelect,
        ),
        listRevision: list,
      );

  FreeTextCandidate unique(String text, String id) => FreeTextCandidate(
        text: text,
        matchType: VoiceListMatchType.unique,
        itemId: id,
      );

  test('T04 false command partial cannot claim mobile dynamic item', () {
    final VoiceUtteranceCoordinator coordinator = VoiceUtteranceCoordinator();
    final VoiceDecisionContext current = context();
    final VoiceDecision result = coordinator.decide(
      context: current,
      currentContext: current,
      freeText: unique('мобильный', 'mobile'),
      itemStillExists: (_) => true,
    );
    expect(result.kind, VoiceDecisionKind.dynamicItem);
  });

  for (final (String name, WearVoiceCommand command)
      in <(String, WearVoiceCommand)>[
    ('T05 up remains immediate', WearVoiceCommand.up),
    ('T06 down remains immediate', WearVoiceCommand.down),
  ]) {
    test(name, () {
      final VoiceUtteranceCoordinator coordinator = VoiceUtteranceCoordinator();
      final VoiceDecisionContext current = context();
      expect(
        coordinator.claimImmediate(current, command).kind,
        VoiceDecisionKind.immediateCommand,
      );
      expect(
        coordinator
            .decide(
              context: current,
              currentContext: current,
              freeText: unique('жёлтый', 'yellow'),
              itemStillExists: (_) => true,
            )
            .kind,
        VoiceDecisionKind.none,
      );
    });
  }

  test('T07 endpoint-only partial does not suppress yellow', () {
    final VoiceUtteranceCoordinator coordinator = VoiceUtteranceCoordinator();
    final VoiceDecisionContext current = context();
    expect(
      coordinator
          .decide(
            context: current,
            currentContext: current,
            freeText: unique('жёлтый', 'yellow'),
            itemStillExists: (_) => true,
          )
          .kind,
      VoiceDecisionKind.dynamicItem,
    );
  });

  test('T08 same semantic result publishes command once', () {
    final VoiceUtteranceCoordinator coordinator = VoiceUtteranceCoordinator();
    final VoiceDecisionContext current = context();
    final VoiceDecision decision = coordinator.decide(
      context: current,
      currentContext: current,
      command: const CommandCandidate(
        command: WearVoiceCommand.back,
        text: 'назад',
      ),
      freeText: const FreeTextCandidate(
        text: 'назад',
        matchType: VoiceListMatchType.none,
      ),
      itemStillExists: (_) => false,
    );
    expect(decision.kind, VoiceDecisionKind.command);
    expect(
      coordinator
          .decide(
            context: current,
            currentContext: current,
            itemStillExists: (_) => false,
          )
          .kind,
      VoiceDecisionKind.none,
    );
  });

  test('T09 command-only result publishes command', () {
    final VoiceUtteranceCoordinator coordinator = VoiceUtteranceCoordinator();
    final VoiceDecisionContext current = context();
    expect(
      coordinator
          .decide(
            context: current,
            currentContext: current,
            command: const CommandCandidate(
              command: WearVoiceCommand.back,
              text: 'назад',
            ),
            itemStillExists: (_) => false,
          )
          .kind,
      VoiceDecisionKind.command,
    );
  });

  test('T10 command takes priority over a unique dynamic item', () {
    final VoiceUtteranceCoordinator coordinator = VoiceUtteranceCoordinator();
    final VoiceDecisionContext current = context();
    expect(
      coordinator
          .decide(
            context: current,
            currentContext: current,
            command: const CommandCandidate(
              command: WearVoiceCommand.select,
              text: 'выбрать',
            ),
            freeText: unique('жёлтый', 'yellow'),
            itemStillExists: (_) => true,
          )
          .kind,
      VoiceDecisionKind.command,
    );
  });

  test('exact advertised hint takes priority over a conflicting command', () {
    final VoiceUtteranceCoordinator coordinator = VoiceUtteranceCoordinator();
    final VoiceDecisionContext current = context();

    final VoiceDecision decision = coordinator.decide(
      context: current,
      currentContext: current,
      command: const CommandCandidate(
        command: WearVoiceCommand.back,
        text: 'назад',
      ),
      freeText: const FreeTextCandidate(
        text: 'безалкогольное',
        matchType: VoiceListMatchType.unique,
        itemId: 'drinks',
        isExactHint: true,
      ),
      itemStillExists: (_) => true,
    );

    expect(decision.kind, VoiceDecisionKind.dynamicItem);
  });

  test('stable dynamic match takes priority over a conflicting home command',
      () {
    final VoiceUtteranceCoordinator coordinator = VoiceUtteranceCoordinator();
    final VoiceDecisionContext current = context();

    final VoiceDecision decision = coordinator.decide(
      context: current,
      currentContext: current,
      command: const CommandCandidate(
        command: WearVoiceCommand.home,
        text: 'домой',
      ),
      freeText: const FreeTextCandidate(
        text: 'безалкогольное',
        matchType: VoiceListMatchType.unique,
        itemId: '2',
        isStableMatch: true,
      ),
      itemStillExists: (_) => true,
    );

    expect(decision.kind, VoiceDecisionKind.dynamicItem);
  });

  test('T11 ambiguous dynamic result is rejected', () {
    final VoiceUtteranceCoordinator coordinator = VoiceUtteranceCoordinator();
    final VoiceDecisionContext current = context();
    expect(
      coordinator
          .decide(
            context: current,
            currentContext: current,
            freeText: const FreeTextCandidate(
              text: 'белый',
              matchType: VoiceListMatchType.ambiguous,
            ),
            itemStillExists: (_) => true,
          )
          .kind,
      VoiceDecisionKind.ambiguousRejected,
    );
  });

  test('T16 route change invalidates candidates', () {
    final VoiceUtteranceCoordinator coordinator = VoiceUtteranceCoordinator();
    expect(
      coordinator
          .decide(
            context: context(),
            currentContext: context(route: 2),
            freeText: unique('жёлтый', 'yellow'),
            itemStillExists: (_) => true,
          )
          .kind,
      VoiceDecisionKind.stale,
    );
  });

  test('T17 capture restart invalidates old boundary', () {
    final VoiceUtteranceCoordinator coordinator = VoiceUtteranceCoordinator();
    expect(
      coordinator
          .decide(
            context: context(),
            currentContext: context(capture: 2),
            freeText: unique('жёлтый', 'yellow'),
            itemStillExists: (_) => true,
          )
          .kind,
      VoiceDecisionKind.stale,
    );
  });

  test('T18 free-text epoch change invalidates old result', () {
    final VoiceUtteranceCoordinator coordinator = VoiceUtteranceCoordinator();
    expect(
      coordinator
          .decide(
            context: context(),
            currentContext: context(freeText: 2),
            freeText: unique('жёлтый', 'yellow'),
            itemStillExists: (_) => true,
          )
          .kind,
      VoiceDecisionKind.stale,
    );
  });

  test('list revision and removed item invalidate dynamic result', () {
    final VoiceUtteranceCoordinator coordinator = VoiceUtteranceCoordinator();
    expect(
      coordinator
          .decide(
            context: context(),
            currentContext: context(list: 2),
            freeText: unique('жёлтый', 'yellow'),
            itemStillExists: (_) => true,
          )
          .kind,
      VoiceDecisionKind.stale,
    );
    final VoiceDecisionContext second = context(utterance: 2);
    expect(
      coordinator
          .decide(
            context: second,
            currentContext: second,
            freeText: unique('жёлтый', 'yellow'),
            itemStillExists: (_) => false,
          )
          .kind,
      VoiceDecisionKind.none,
    );
  });

  test('T21 every candidate combination publishes at most one intent', () {
    for (final bool hasCommand in <bool>[false, true]) {
      for (final VoiceListMatchType match in VoiceListMatchType.values) {
        final VoiceUtteranceCoordinator coordinator =
            VoiceUtteranceCoordinator();
        final VoiceDecisionContext current =
            context(utterance: match.index + (hasCommand ? 10 : 20));
        final VoiceDecision first = coordinator.decide(
          context: current,
          currentContext: current,
          command: hasCommand
              ? const CommandCandidate(
                  command: WearVoiceCommand.select,
                  text: 'выбрать',
                )
              : null,
          freeText: FreeTextCandidate(
            text: match == VoiceListMatchType.none ? '' : 'жёлтый',
            matchType: match,
            itemId: match == VoiceListMatchType.unique ? 'yellow' : null,
          ),
          itemStillExists: (_) => true,
        );
        final VoiceDecision second = coordinator.decide(
          context: current,
          currentContext: current,
          itemStillExists: (_) => true,
        );
        expect(first.intent == null ? 0 : 1, lessThanOrEqualTo(1));
        expect(second.intent, isNull);
      }
    }
  });
}
