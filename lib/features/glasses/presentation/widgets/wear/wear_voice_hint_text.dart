import 'package:flutter/material.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

class WearVoiceHintText extends StatelessWidget {
  const WearVoiceHintText({
    super.key,
    required this.text,
    required this.style,
    this.hint,
  });

  final String text;
  final TextStyle style;
  final WearGlassesVoiceHint? hint;

  @override
  Widget build(BuildContext context) {
    final WearGlassesVoiceHint? value = hint;
    return Text.rich(
      value == null || !value.isValidFor(text)
          ? TextSpan(text: text)
          : TextSpan(children: <InlineSpan>[
              if (value.start > 0)
                TextSpan(text: text.substring(0, value.start)),
              TextSpan(
                text: text.substring(value.start, value.end),
                style: const TextStyle(decoration: TextDecoration.underline),
              ),
              if (value.end < text.length)
                TextSpan(text: text.substring(value.end)),
            ]),
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
