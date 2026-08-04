import 'dart:async';
import 'dart:ui' as ui;

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

class MarqueeText extends StatefulWidget {
  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.hint,
    this.selected = false,
  });

  final String text;
  final TextStyle style;
  final WearGlassesVoiceHint? hint;
  final bool selected;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _pendingTimer;
  bool _marqueeActive = false;
  double _scrollDistance = 0;

  static const Duration _startPause = Duration(milliseconds: 500);
  static const Duration _endPause = Duration(milliseconds: 1000);
  static const Duration _scrollDuration = Duration(milliseconds: 3300);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _controller.addStatusListener(_onStatus);
  }

  @override
  void didUpdateWidget(MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      if (!widget.selected) {
        _stopMarquee();
      }
    }
  }

  @override
  void dispose() {
    _cancelPendingTimer();
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _scheduleTimer(_endPause, _controller.reverse);
    } else if (status == AnimationStatus.dismissed) {
      _scheduleTimer(_startPause, _controller.forward);
    }
  }

  void _scheduleTimer(Duration delay, VoidCallback callback) {
    _cancelPendingTimer();
    _pendingTimer = Timer(delay, () {
      if (mounted && _marqueeActive) {
        callback();
      }
    });
  }

  void _cancelPendingTimer() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
  }

  void _stopMarquee() {
    _cancelPendingTimer();
    _controller.stop();
    _controller.value = 0;
    _marqueeActive = false;
    _scrollDistance = 0;
  }

  void _startMarquee(double scrollDistance) {
    _marqueeActive = true;
    _scrollDistance = scrollDistance;
    _controller.stop();
    _controller.duration = _scrollDuration;
    _controller.value = 0;
    _scheduleTimer(_startPause, _controller.forward);
  }

  void _onLayout(double availableWidth, double textWidth) {
    final bool overflows = textWidth > availableWidth + 1;
    final bool shouldMarquee = widget.selected && overflows;

    if (shouldMarquee && !_marqueeActive) {
      final double distance =
          (textWidth - availableWidth).clamp(0.0, double.infinity);
      _startMarquee(distance);
      setState(() {});
    } else if (!shouldMarquee && _marqueeActive) {
      _stopMarquee();
      setState(() {});
    } else if (shouldMarquee && _marqueeActive) {
      final double distance =
          (textWidth - availableWidth).clamp(0.0, double.infinity);
      if ((distance - _scrollDistance).abs() > 1) {
        _startMarquee(distance);
      }
    }
  }

  double _measureTextWidth() {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    );
    painter.layout(maxWidth: double.infinity);
    final double width = painter.width;
    painter.dispose();
    return width;
  }

  TextSpan _buildSpan() {
    final WearGlassesVoiceHint? value = widget.hint;
    if (value == null || !value.isValidFor(widget.text)) {
      return TextSpan(text: widget.text, style: widget.style);
    }
    return TextSpan(
      style: widget.style,
      children: <InlineSpan>[
        if (value.start > 0)
          TextSpan(text: widget.text.substring(0, value.start)),
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: widget.style.color ?? Colors.white,
                  width: 2,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                widget.text.substring(value.start, value.end),
                style: widget.style,
              ),
            ),
          ),
        ),
        if (value.end < widget.text.length)
          TextSpan(text: widget.text.substring(value.end)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double availableWidth = constraints.maxWidth;
        final double textWidth = _measureTextWidth();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _onLayout(availableWidth, textWidth);
          }
        });

        if (!_marqueeActive) {
          return WearVoiceHintText(
            text: widget.text,
            style: widget.style,
            hint: widget.hint,
          );
        }

        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext context, Widget? child) {
              final double t = Curves.easeInOut.transform(_controller.value);
              return Transform.translate(
                offset: Offset(-t * _scrollDistance, 0),
                child: child,
              );
            },
            child: Text.rich(
              _buildSpan(),
              maxLines: 1,
            ),
          ),
        );
      },
    );
  }
}
