import 'dart:async';

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

class _MarqueeTextState extends State<MarqueeText> {
  final ScrollController _scrollController = ScrollController();
  Timer? _pendingTimer;
  bool _marqueeActive = false;
  double _scrollExtent = 0;
  int _animationGeneration = 0;

  static const Duration _startPause = Duration(milliseconds: 500);
  static const Duration _endPause = Duration(milliseconds: 1000);
  // 3300 ms / 0.8: the movement is exactly 20% slower than before.
  static const Duration _scrollDuration = Duration(milliseconds: 4125);

  @override
  void didUpdateWidget(MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool contentChanged = oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        !_sameHint(oldWidget.hint, widget.hint);
    if (oldWidget.selected != widget.selected || contentChanged) {
      _resetMarquee();
    }
  }

  @override
  void dispose() {
    _animationGeneration++;
    _cancelPendingTimer();
    _scrollController.dispose();
    super.dispose();
  }

  static bool _sameHint(
    WearGlassesVoiceHint? left,
    WearGlassesVoiceHint? right,
  ) {
    if (identical(left, right)) return true;
    if (left == null || right == null) return false;
    return left.itemId == right.itemId &&
        left.phrase == right.phrase &&
        left.start == right.start &&
        left.end == right.end;
  }

  void _cancelPendingTimer() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
  }

  void _scheduleTimer(Duration delay, VoidCallback callback) {
    _cancelPendingTimer();
    _pendingTimer = Timer(delay, () {
      if (mounted && _marqueeActive && widget.selected) {
        callback();
      }
    });
  }

  void _resetMarquee() {
    _animationGeneration++;
    _cancelPendingTimer();
    _marqueeActive = false;
    _scrollExtent = 0;
    if (_scrollController.hasClients && _scrollController.offset != 0) {
      _scrollController.jumpTo(0);
    }
  }

  void _syncMarqueeAfterLayout() {
    if (!mounted || !widget.selected || !_scrollController.hasClients) return;
    final double extent = _scrollController.position.maxScrollExtent;
    if (extent <= 1) {
      if (_marqueeActive || _scrollController.offset != 0) {
        _resetMarquee();
      }
      return;
    }
    if (_marqueeActive && (extent - _scrollExtent).abs() <= 1) return;
    _startMarquee(extent);
  }

  void _startMarquee(double extent) {
    _animationGeneration++;
    final int generation = _animationGeneration;
    _cancelPendingTimer();
    _marqueeActive = true;
    _scrollExtent = extent;
    if (_scrollController.hasClients && _scrollController.offset != 0) {
      _scrollController.jumpTo(0);
    }
    _scheduleTimer(
      _startPause,
      () => unawaited(_animateToEnd(generation)),
    );
  }

  bool _canAnimate(int generation) {
    return mounted &&
        widget.selected &&
        _marqueeActive &&
        generation == _animationGeneration &&
        _scrollController.hasClients;
  }

  Future<void> _animateToEnd(int generation) async {
    if (!_canAnimate(generation)) return;
    final double target = _scrollController.position.maxScrollExtent;
    if (target <= 1) {
      _resetMarquee();
      return;
    }
    try {
      await _scrollController.animateTo(
        target,
        duration: _scrollDuration,
        curve: Curves.easeInOut,
      );
    } catch (_) {
      return;
    }
    if (!_canAnimate(generation)) return;
    _scheduleTimer(
      _endPause,
      () => unawaited(_animateToStart(generation)),
    );
  }

  Future<void> _animateToStart(int generation) async {
    if (!_canAnimate(generation)) return;
    try {
      await _scrollController.animateTo(
        0,
        duration: _scrollDuration,
        curve: Curves.easeInOut,
      );
    } catch (_) {
      return;
    }
    if (!_canAnimate(generation)) return;
    _scheduleTimer(
      _startPause,
      () => unawaited(_animateToEnd(generation)),
    );
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
    if (!widget.selected) {
      return WearVoiceHintText(
        text: widget.text,
        style: widget.style,
        hint: widget.hint,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncMarqueeAfterLayout();
    });

    return ClipRect(
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Text.rich(
          _buildSpan(),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
        ),
      ),
    );
  }
}
