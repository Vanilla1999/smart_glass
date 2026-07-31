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
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: style.color ?? Colors.white,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      text.substring(value.start, value.end),
                      style: style,
                    ),
                  ),
                ),
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
