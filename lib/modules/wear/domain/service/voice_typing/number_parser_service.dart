import 'package:smart_glasses/modules/wear/domain/service/voice_typing/tokenizer.dart';

enum _FsmPhase { start, haveHundreds, haveTens, haveTeen, haveUnit }

class NumberParserService {
  NumberParserService({
    NumberTokenizer? tokenizer,
  }) : _tokenizer = tokenizer ?? const NumberTokenizer();

  final NumberTokenizer _tokenizer;
  final int _maxRepeat = 19;

  static const int _initialScale = 9223372036854775807;

  /// Переводит текущую строку с числительными и прочими словами
  /// на русском языке в готовую строку из цифр.
  ///
  /// Например:
  /// - `триста девяносто пять` -> `395`
  /// - `триста девяносто пять девяносто семь четыре` -> `395974`
  ///
  /// Строка всегда будет распознаваться как одно число при возможных
  /// расхождениях. Т.е. `семьдесят тысяч пятьдесят три` -> `70053`, а не
  /// `7000053`.
  String parseToNumber(String input) {
    final tokens = _tokenizer.tokenize(input);
    final out = StringBuffer();

    var total = 0;
    var group = 0;
    var phase = _FsmPhase.start;
    var lastScale = _initialScale;
    var hasNumber = false;

    void resetState() {
      total = 0;
      group = 0;
      phase = _FsmPhase.start;
      lastScale = _initialScale;
      hasNumber = false;
    }

    void emitDigits(String digits, String reason) {
      out.write(digits);
      print('EMIT[$reason]: $digits');
    }

    void flush(String reason) {
      if (!hasNumber) {
        return;
      }

      final value = total + group;
      emitDigits(value.toString(), 'FLUSH:$reason');
      resetState();
    }

    for (final token in tokens) {
      switch (token.type) {
        case NumberTokenType.digitNoun:
          if (!hasNumber) {
            emitDigits(token.value.toString(), 'DIGIT_NOUN_SINGLE');
            resetState();
            break;
          }

          var count = total + group;
          if (count < 0) {
            count = 0;
          }
          // Обработка, чтобы нельзя было сказать "восемьдесят три нуля" и
          // и получить 83 нуля одной строкой, а получить "83000".
          if (count > _maxRepeat) {
            final repeatTail = group % 10;
            final prefix = count - repeatTail;
            if (prefix > 0) {
              emitDigits(prefix.toString(), 'FLUSH:repeat-limit');
            }
            count = repeatTail;
          }

          final repeatedChunk =
              List<String>.filled(count, token.value.toString()).join();
          emitDigits(repeatedChunk, 'REPEAT d=${token.value} x$count');
          resetState();
          break;

        case NumberTokenType.unit:
          if (token.value == 0) {
            flush('before-zero');
            emitDigits('0', 'ZERO');
            resetState();
            break;
          }

          switch (phase) {
            case _FsmPhase.start:
            case _FsmPhase.haveHundreds:
            case _FsmPhase.haveTens:
              group += token.value;
              phase = _FsmPhase.haveUnit;
              hasNumber = true;
              break;

            case _FsmPhase.haveTeen:
            case _FsmPhase.haveUnit:
              flush('unit-after-closed');
              group = token.value;
              phase = _FsmPhase.haveUnit;
              hasNumber = true;
              break;
          }
          break;

        case NumberTokenType.teen:
          if (phase == _FsmPhase.start || phase == _FsmPhase.haveHundreds) {
            group += token.value;
            phase = _FsmPhase.haveTeen;
            hasNumber = true;
          } else {
            flush('teen-mismatch');
            group = token.value;
            phase = _FsmPhase.haveTeen;
            hasNumber = true;
          }
          break;

        case NumberTokenType.tens:
          if (phase == _FsmPhase.start || phase == _FsmPhase.haveHundreds) {
            group += token.value;
            phase = _FsmPhase.haveTens;
            hasNumber = true;
          } else {
            flush('tens-mismatch');
            group = token.value;
            phase = _FsmPhase.haveTens;
            hasNumber = true;
          }
          break;

        case NumberTokenType.hundred:
          if (phase == _FsmPhase.start) {
            group += token.value;
            phase = _FsmPhase.haveHundreds;
            hasNumber = true;
          } else {
            flush('hundred-mismatch');
            group = token.value;
            phase = _FsmPhase.haveHundreds;
            hasNumber = true;
          }
          break;

        case NumberTokenType.scale:
          final scale = token.value;

          if (!hasNumber) {
            group = 1;
            phase = _FsmPhase.haveUnit;
            hasNumber = true;
          }

          if (scale >= lastScale) {
            final preservedGroup = group;
            final preservedPhase = phase;
            final hasCompletedScaledPart = total != 0;

            if (hasCompletedScaledPart && preservedGroup != 0) {
              // Граница должна идти перед новой группой:
              // "два тысяч три тысячи" => "2000" + "3000", а не "2003" + "1000".
              emitDigits(total.toString(), 'FLUSH:scale-order');
              total = 0;
              group = preservedGroup;
              phase = preservedPhase;
              lastScale = _initialScale;
              hasNumber = true;
            } else {
              flush('scale-order');
              group = 1;
              phase = _FsmPhase.haveUnit;
              hasNumber = true;
            }
          }

          total += (group > 0 ? group : 1) * scale;
          group = 0;
          phase = _FsmPhase.start;
          lastScale = scale;
          hasNumber = true;
          break;
      }
    }

    flush('eof');
    final result = out.toString();
    print('RESULT: $result');
    return result;
  }
}
