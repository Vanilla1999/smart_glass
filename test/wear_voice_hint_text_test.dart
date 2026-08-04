import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/features/glasses/presentation/widgets/wear/wear_voice_hint_text.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

const TextStyle _style = TextStyle(fontSize: 20, color: Colors.white);
const String _longText =
    'Имунеле напиток кисломолочный клубничный большой упаковки';
const WearGlassesVoiceHint _hint = WearGlassesVoiceHint(
  itemId: '1',
  phrase: 'имунеле',
  start: 0,
  end: 7,
);

void main() {
  Widget buildMarquee({
    required String text,
    required bool selected,
    WearGlassesVoiceHint? voiceHint = _hint,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 150,
            child: MarqueeText(
              key: const ValueKey<String>('marquee'),
              text: text,
              style: _style,
              hint: voiceHint,
              selected: selected,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('selected text scrolls the full hidden tail to the end and back',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildMarquee(text: _longText, selected: true));
    await tester.pump();

    final ScrollableState scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    expect(scrollable.position.pixels, 0);

    await tester.pump(const Duration(milliseconds: 500));
    expect(scrollable.position.pixels, 0);

    await tester.pump(const Duration(milliseconds: 2062));
    expect(scrollable.position.pixels, greaterThan(0));
    expect(
      scrollable.position.pixels,
      lessThan(scrollable.position.maxScrollExtent),
    );

    await tester.pump(const Duration(milliseconds: 2063));
    expect(
      scrollable.position.pixels,
      moreOrLessEquals(scrollable.position.maxScrollExtent, epsilon: 0.5),
    );

    await tester.pump(const Duration(milliseconds: 1000));
    expect(
      scrollable.position.pixels,
      moreOrLessEquals(scrollable.position.maxScrollExtent, epsilon: 0.5),
    );

    await tester.pump(const Duration(milliseconds: 4125));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(scrollable.position.pixels, moreOrLessEquals(0, epsilon: 0.5));
  });

  testWidgets('selected text renders full content without inner ellipsis',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildMarquee(text: _longText, selected: true));
    await tester.pump();

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    final Finder movingTextFinder = find.descendant(
      of: find.byType(SingleChildScrollView),
      matching: find.byWidgetPredicate(
        (Widget widget) =>
            widget is Text && widget.overflow == TextOverflow.visible,
      ),
    );
    expect(movingTextFinder, findsOneWidget);
    final Text movingText = tester.widget<Text>(movingTextFinder);
    expect(movingText.softWrap, isFalse);
  });

  testWidgets('changing text resets the selected row to the beginning',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildMarquee(text: _longText, selected: true));
    await tester.pump();
    final ScrollableState initial =
        tester.state<ScrollableState>(find.byType(Scrollable));

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 2000));
    expect(initial.position.pixels, greaterThan(0));

    await tester.pumpWidget(
      buildMarquee(
        text: 'Аа',
        selected: true,
        voiceHint: null,
      ),
    );
    await tester.pump();

    final ScrollableState updated =
        tester.state<ScrollableState>(find.byType(Scrollable));
    expect(updated.position.pixels, 0);
    expect(updated.position.maxScrollExtent, 0);
  });

  testWidgets('unselected text keeps the previous ellipsis rendering',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      buildMarquee(
        text: _longText,
        selected: false,
        voiceHint: null,
      ),
    );

    expect(find.byType(SingleChildScrollView), findsNothing);
    final Finder staticTextFinder = find.byWidgetPredicate(
      (Widget widget) =>
          widget is Text && widget.overflow == TextOverflow.ellipsis,
    );
    expect(staticTextFinder, findsOneWidget);
    final Text staticText = tester.widget<Text>(staticTextFinder);
    expect(staticText.maxLines, 1);
  });
}
