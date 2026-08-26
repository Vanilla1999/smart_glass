import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/wear/wear_scan_overlay_cubit.dart';
import 'package:smart_glasses/features/glasses/presentation/widgets/wear/wear_scan_overlay.dart';

void main() {
  test('rejects stale revisions and clears stale candidate', () async {
    final WearScanOverlayCubit cubit = WearScanOverlayCubit();
    addTearDown(cubit.close);

    cubit.update(<String, dynamic>{
      'visible': true,
      'revision': 2,
      'phase': 'candidate',
      'left': 0.6,
      'right': 0.8,
      'top': 0.2,
      'bottom': 0.4,
    });
    cubit.update(<String, dynamic>{
      'visible': false,
      'revision': 1,
      'phase': 'clear',
    });

    expect(cubit.state.phase, WearScanOverlayPhase.candidate);
    expect(cubit.state.centerX, closeTo(0.7, 0.0001));
    await Future<void>.delayed(const Duration(milliseconds: 1025));
    expect(cubit.state.phase, WearScanOverlayPhase.searching);
    expect(cubit.state.centerX, 0.5);
  });

  test('accepts revisions from a new overlay session', () {
    final WearScanOverlayCubit cubit = WearScanOverlayCubit();
    addTearDown(cubit.close);

    cubit.update(<String, dynamic>{
      'sessionId': 1,
      'visible': false,
      'revision': 100,
      'phase': 'clear',
    });
    cubit.update(<String, dynamic>{
      'sessionId': 2,
      'visible': true,
      'revision': 1,
      'phase': 'searching',
    });

    expect(cubit.state.sessionId, 2);
    expect(cubit.state.revision, 1);
    expect(cubit.state.visible, isTrue);
  });

  test('rejects delayed payload from an older overlay session', () {
    final WearScanOverlayCubit cubit = WearScanOverlayCubit();
    addTearDown(cubit.close);

    cubit.update(<String, dynamic>{
      'sessionId': 2,
      'revision': 1,
      'visible': true,
      'phase': 'searching',
    });
    cubit.update(<String, dynamic>{
      'sessionId': 1,
      'revision': 100,
      'visible': false,
      'phase': 'clear',
    });

    expect(cubit.state.sessionId, 2);
    expect(cubit.state.visible, isTrue);
  });

  test('does not clear a locked candidate on a timer', () async {
    final WearScanOverlayCubit cubit = WearScanOverlayCubit();
    addTearDown(cubit.close);

    cubit.update(<String, dynamic>{
      'visible': true,
      'revision': 1,
      'phase': 'locked',
      'left': 0.6,
      'right': 0.8,
      'top': 0.2,
      'bottom': 0.4,
    });
    await Future<void>.delayed(const Duration(milliseconds: 1025));

    expect(cubit.state.phase, WearScanOverlayPhase.locked);
    expect(cubit.state.centerX, closeTo(0.7, 0.0001));
  });

  test('smooths one candidate and resets for a different candidate', () {
    final WearScanOverlayCubit cubit = WearScanOverlayCubit();
    addTearDown(cubit.close);

    void update({
      required int revision,
      required int candidateId,
      required int detectedAtNanos,
      required double centerX,
    }) {
      cubit.update(<String, dynamic>{
        'visible': true,
        'revision': revision,
        'phase': 'candidate',
        'candidateId': candidateId,
        'detectedAtElapsedRealtimeNanos': detectedAtNanos,
        'left': centerX - 0.1,
        'right': centerX + 0.1,
        'top': 0.4,
        'bottom': 0.6,
      });
    }

    update(
      revision: 1,
      candidateId: 10,
      detectedAtNanos: 1_000_000_000,
      centerX: 0.5,
    );
    update(
      revision: 2,
      candidateId: 10,
      detectedAtNanos: 1_067_000_000,
      centerX: 0.52,
    );

    expect(cubit.state.centerX, greaterThan(0.5));
    expect(cubit.state.centerX, lessThan(0.52));

    update(
      revision: 3,
      candidateId: 11,
      detectedAtNanos: 1_134_000_000,
      centerX: 0.8,
    );
    expect(cubit.state.centerX, closeTo(0.8, 0.0001));
  });

  testWidgets('renders reticle and moves to candidate center',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(640, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final WearScanOverlayCubit cubit = WearScanOverlayCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      BlocProvider<WearScanOverlayCubit>.value(
        value: cubit,
        child: const MaterialApp(
          home: SizedBox(
            width: 640,
            height: 480,
            child: WearScanOverlay(visible: true),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('wear-scan-reticle')), findsOneWidget);

    cubit.update(<String, dynamic>{
      'visible': true,
      'revision': 1,
      'phase': 'candidate',
      'left': 0.6,
      'right': 0.8,
      'top': 0.2,
      'bottom': 0.4,
    });
    await tester.pump();

    expect(find.byKey(const Key('wear-scan-reticle')), findsOneWidget);
    final AnimatedSlide slide = tester.widget<AnimatedSlide>(
      find.ancestor(
        of: find.byKey(const Key('wear-scan-reticle')),
        matching: find.byType(AnimatedSlide),
      ),
    );
    expect(slide.offset.dx, closeTo(338 / 220, 0.0001));
    expect(slide.offset.dy, closeTo(84 / 120, 0.0001));
    await tester.pump(const Duration(milliseconds: 1025));
    await tester.pumpAndSettle();
  });
}
