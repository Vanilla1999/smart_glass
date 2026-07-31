import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/features/glasses/presentation/widgets/wear/wear_voice_hint_text.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

void main() {
  testWidgets('underlines only the voice hint range',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: WearVoiceHintText(
        text: 'MOCK Белый 1',
        style: TextStyle(fontWeight: FontWeight.w400),
        hint: WearGlassesVoiceHint(
          itemId: 'printer-1',
          phrase: 'белый',
          start: 5,
          end: 10,
        ),
      ),
    ));

    final Text text = tester.widget<Text>(find.byType(Text));
    final TextSpan root = text.textSpan! as TextSpan;
    final List<InlineSpan> spans = root.children!;

    expect((spans[0] as TextSpan).text, 'MOCK ');
    expect((spans[1] as TextSpan).text, 'Белый');
    expect(
      (spans[1] as TextSpan).style?.decoration,
      TextDecoration.underline,
    );
    expect((spans[1] as TextSpan).style?.fontWeight, isNull);
    expect((spans[2] as TextSpan).text, ' 1');
  });

  testWidgets('invalid range falls back to plain text',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: WearVoiceHintText(
        text: 'Принтер',
        style: TextStyle(fontWeight: FontWeight.w400),
        hint: WearGlassesVoiceHint(
          itemId: 'printer-1',
          phrase: 'принтер',
          start: 4,
          end: 99,
        ),
      ),
    ));

    final Text text = tester.widget<Text>(find.byType(Text));
    final TextSpan root = text.textSpan! as TextSpan;
    expect(root.text, 'Принтер');
    expect(root.children, isNull);
  });
}
