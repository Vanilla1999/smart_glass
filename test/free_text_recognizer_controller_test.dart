import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/free_text_recognizer_controller.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_typing/voice_replay_policy.dart';

void main() {
  test('concurrent enable shares one creation', () async {
    final Completer<_Recognizer> creation = Completer<_Recognizer>();
    var creates = 0;
    final controller = _controller(() {
      creates++;
      return creation.future;
    });

    final Future<_Recognizer?> first = controller.enable();
    final Future<_Recognizer?> second = controller.enable();
    final _Recognizer recognizer = _Recognizer();
    creation.complete(recognizer);

    expect(await first, same(recognizer));
    expect(await second, same(recognizer));
    expect(creates, 1);
    expect(controller.state, FreeTextRecognizerState.ready);
  });

  test('disable during create safely disposes late recognizer', () async {
    final Completer<_Recognizer> creation = Completer<_Recognizer>();
    final controller = _controller(() => creation.future);
    final Future<_Recognizer?> enabling = controller.enable();

    controller.disable();
    final _Recognizer stale = _Recognizer();
    creation.complete(stale);

    expect(await enabling, isNull);
    expect(stale.disposeCalls, 1);
    expect(controller.state, FreeTextRecognizerState.absent);
  });

  test('concurrent recovery is deduplicated', () async {
    final _Recognizer failed = _Recognizer();
    final Completer<_Recognizer> recovery = Completer<_Recognizer>();
    var creates = 0;
    final controller = _controller(() {
      creates++;
      return creates == 1 ? Future<_Recognizer>.value(failed) : recovery.future;
    });
    await controller.enable();

    final Future<_Recognizer?> first = controller.recover(
      failed,
      commandWorkPending: true,
    );
    final Future<_Recognizer?> second = controller.recover(
      failed,
      commandWorkPending: true,
    );
    final _Recognizer replacement = _Recognizer();
    recovery.complete(replacement);

    expect(await first, same(replacement));
    expect(await second, same(replacement));
    expect(creates, 2);
  });

  test('stale late recovery completion cannot replace newer generation',
      () async {
    final Completer<_Recognizer> firstCreation = Completer<_Recognizer>();
    final Completer<_Recognizer> secondCreation = Completer<_Recognizer>();
    var creates = 0;
    final controller = _controller(
      () => ++creates == 1 ? firstCreation.future : secondCreation.future,
    );
    final Future<_Recognizer?> first = controller.enable();
    controller.disable();
    final Future<_Recognizer?> second = controller.enable();
    final _Recognizer stale = _Recognizer();
    firstCreation.complete(stale);
    final _Recognizer current = _Recognizer();
    secondCreation.complete(current);

    expect(await first, isNull);
    expect(await second, same(current));
    expect(controller.recognizer, same(current));
    expect(stale.disposeCalls, 1);
  });

  test('abandoned hung creation does not block replacement', () async {
    final Completer<_Recognizer> hung = Completer<_Recognizer>();
    var creates = 0;
    final controller = _controller(
      () => ++creates == 1
          ? hung.future
          : Future<_Recognizer>.value(_Recognizer()),
    );
    controller.enable();

    controller.abandonCreation();
    final _Recognizer? replacement = await controller.enable();

    expect(replacement, isNotNull);
    expect(creates, 2);
    final _Recognizer stale = _Recognizer();
    hung.complete(stale);
    await Future<void>.delayed(Duration.zero);
    expect(stale.disposeCalls, 1);
  });

  test('dispose waits for pending native operation before recognizer disposal',
      () async {
    final _Recognizer recognizer = _Recognizer();
    final Completer<void> pending = Completer<void>();
    final controller = _controller(
      () => Future<_Recognizer>.value(recognizer),
    );
    await controller.enable();

    var completed = false;
    final Future<void> disposal = controller
        .dispose(pendingOperation: pending.future)
        .then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    expect(recognizer.disposeCalls, 0);

    pending.complete();
    await disposal;
    expect(recognizer.disposeCalls, 1);
  });

  test('native timeout preserves every typed stage', () async {
    const VoiceNativeTimeoutPolicy policy = VoiceNativeTimeoutPolicy(
      waitReady: Duration(milliseconds: 1),
      create: Duration(milliseconds: 1),
      reset: Duration(milliseconds: 1),
      accept: Duration(milliseconds: 1),
      endpointResult: Duration(milliseconds: 1),
      finalResult: Duration(milliseconds: 1),
      dispose: Duration(milliseconds: 1),
    );
    for (final ReplayNativeStage stage in ReplayNativeStage.values) {
      await expectLater(
        policy.run<void>(stage, Completer<void>().future),
        throwsA(
          isA<ReplayNativeTimeoutException>().having(
            (ReplayNativeTimeoutException error) => error.stage,
            'stage',
            stage,
          ),
        ),
      );
    }
  });
}

FreeTextRecognizerController<_Recognizer> _controller(
  Future<_Recognizer> Function() create,
) {
  return FreeTextRecognizerController<_Recognizer>(
    create: create,
    dispose: (_Recognizer recognizer) => recognizer.dispose(),
  );
}

class _Recognizer {
  int disposeCalls = 0;

  Future<void> dispose() async {
    disposeCalls++;
  }
}
