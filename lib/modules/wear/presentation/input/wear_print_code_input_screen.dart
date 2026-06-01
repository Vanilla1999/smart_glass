import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/presentation/input/cubit/ear_print_code_input_cubit.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_key_button.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_mode_toggle.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_svg_icon.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_voice_indicator.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

const double _inputIconSize = 30;
const double _okIconSize = 20;
const double _okIconScale = 1.0;
const double _codeFieldHorizontalPadding = 5;

class WearPrintCodeInputScreen extends StatelessWidget {
  const WearPrintCodeInputScreen({
    super.key,
    required this.args,
  });

  static const String route = '/wear_print_code_input';

  final Object? args;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => WearPrintCodeInputCubit(),
      child: WearScreenScaffold(
        child: Padding(
          padding: const EdgeInsets.all(4.5),
          child: BlocBuilder<WearPrintCodeInputCubit, WearPrintCodeInputState>(
            builder: (BuildContext context, WearPrintCodeInputState state) {
              final WearPrintCodeInputCubit c =
                  context.read<WearPrintCodeInputCubit>();

              return Column(
                children: <Widget>[
                  const SizedBox(height: 2),
                  WearModeToggle(
                    isDigits: state.mode == WearCodeInputMode.digits,
                    onDigits: () => c.setMode(WearCodeInputMode.digits),
                    onVoice: () => c.setMode(WearCodeInputMode.voice),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: Center(
                      child: SizedBox(
                        width: double.infinity,
                        child: Stack(
                          children: <Widget>[
                            IgnorePointer(
                              ignoring: state.mode == WearCodeInputMode.voice,
                              child: _CodeDisplay(
                                value: state.value,
                                cursor: state.cursor,
                                isActive:
                                    state.mode == WearCodeInputMode.digits,
                                onCursorChanged: c.setCursor,
                              ),
                            ),
                            if (state.mode == WearCodeInputMode.voice)
                              Positioned.fill(
                                child: Builder(
                                  builder: (BuildContext overlayContext) {
                                    return GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTapDown: (TapDownDetails details) {
                                        final int cursor = _cursorFromTap(
                                          context: overlayContext,
                                          text: state.value,
                                          localPosition: details.localPosition,
                                        );
                                        c.setCursor(cursor);
                                        c.setMode(WearCodeInputMode.digits);
                                      },
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Flexible(
                    flex: 6,
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topCenter,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: state.mode == WearCodeInputMode.digits
                              ? _DigitsKeyboard(
                                  key: const ValueKey<String>('digits'),
                                  value: state.value,
                                  onDigit: c.pressDigit,
                                  onClose: () => context.pop(),
                                  onBackspace: c.backspace,
                                  onSubmit: () => context.pop(state.value),
                                )
                              : _VoiceKeyboard(
                                  key: const ValueKey<String>('voice'),
                                  value: state.value,
                                  phase: state.voicePhase,
                                  level01: c.voiceLevel01,
                                  onClose: () async {
                                    await c.stopVoice();
                                    context.pop();
                                  },
                                  onRetry: () => c.retryVoice(),
                                  onSubmit: () async {
                                    await c.stopVoice();
                                    context.pop(state.value);
                                  },
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(
                    height: 10,
                  )
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  int _cursorFromTap({
    required BuildContext context,
    required String text,
    required Offset localPosition,
  }) {
    if (text.isEmpty) return 0;

    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return text.length;

    const double pad = _codeFieldHorizontalPadding;
    final double width = (box.size.width - pad * 2).clamp(0.0, double.infinity);
    final double dx = (localPosition.dx - pad).clamp(0.0, width);

    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: WearTypography.size20,
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(minWidth: width, maxWidth: width);

    final TextPosition pos =
        painter.getPositionForOffset(Offset(dx, painter.height / 2));
    return pos.offset.clamp(0, text.length);
  }
}

class _CodeDisplay extends StatefulWidget {
  const _CodeDisplay({
    required this.value,
    required this.cursor,
    required this.isActive,
    required this.onCursorChanged,
  });

  final String value;
  final int cursor;
  final bool isActive;
  final ValueChanged<int> onCursorChanged;

  @override
  State<_CodeDisplay> createState() => _CodeDisplayState();
}

class _CodeDisplayState extends State<_CodeDisplay>
    with SingleTickerProviderStateMixin {
  late final _HighlightTextController _controller;
  late final ScrollController _scrollController;
  late final AnimationController _insertAnimation;
  late final FocusNode _focusNode;
  TextRange? _highlightRange;
  bool _syncingSelection = false;
  bool _suppressSelectionCallback = false;
  DateTime _userSelectionUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool _hasHiddenLeft = false;
  bool _hasHiddenRight = false;
  bool _canScroll = false;
  double _scrollRatio = 0;

  @override
  void initState() {
    super.initState();
    _controller = _HighlightTextController();
    _scrollController = ScrollController();
    _focusNode = FocusNode();
    _insertAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..addListener(_applyHighlightFrame);
    _controller.value = TextEditingValue(
      text: widget.value,
      selection: TextSelection.collapsed(offset: _clampCursor(widget.cursor)),
    );
    _controller.addListener(_handleSelectionChanged);
    _scrollController.addListener(_handleScrollChanged);
    _syncScrollVisualStateAfterFrame();
    _ensureCursorVisibleAfterFrame();
    _ensureFocusAfterFrame();
  }

  @override
  void didUpdateWidget(_CodeDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool valueChanged = widget.value != oldWidget.value;
    final bool cursorChanged = widget.cursor != oldWidget.cursor;
    if (valueChanged) {
      _startInsertedTextHighlight(
        oldValue: oldWidget.value,
        newValue: widget.value,
      );
    }
    final int desired = _clampCursor(widget.cursor);
    if (widget.value != _controller.text ||
        _controller.selection.baseOffset != desired) {
      _syncingSelection = true;
      _suppressSelectionCallback = true;
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: desired),
      );
      _syncingSelection = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _suppressSelectionCallback = false;
      });
    }
    if (valueChanged || cursorChanged) {
      _ensureCursorVisibleAfterFrame();
    }
    if (widget.isActive && (!oldWidget.isActive || cursorChanged)) {
      _ensureFocusAfterFrame();
    }
    _syncScrollVisualStateAfterFrame();
  }

  @override
  void dispose() {
    _insertAnimation
      ..removeListener(_applyHighlightFrame)
      ..dispose();
    _controller.removeListener(_handleSelectionChanged);
    _controller.dispose();
    _scrollController.removeListener(_handleScrollChanged);
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSelectionChanged() {
    if (_syncingSelection || _suppressSelectionCallback) return;
    if (DateTime.now().isAfter(_userSelectionUntil)) return;
    final int offset = _controller.selection.baseOffset;
    if (offset < 0) return;
    final int clamped = _clampCursor(offset);
    if (clamped != widget.cursor) {
      widget.onCursorChanged(clamped);
    }
  }

  void _markUserSelectionIntent() {
    _userSelectionUntil = DateTime.now().add(
      const Duration(milliseconds: 450),
    );
  }

  int _clampCursor(int cursor) {
    final int max = widget.value.length;
    if (cursor < 0) return 0;
    if (cursor > max) return max;
    return cursor;
  }

  void _ensureCursorVisibleAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final TextPainter fullPainter = TextPainter(
        text: TextSpan(text: widget.value, style: WearTypography.size20),
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();

      final ScrollPosition position = _scrollController.position;
      final double viewport = position.viewportDimension;
      final double maxScroll = position.maxScrollExtent;

      if (fullPainter.width <= viewport + 0.5) {
        if (position.pixels.abs() > 0.5) {
          _scrollController.jumpTo(0);
        }
        _updateScrollVisualState();
        return;
      }
      final int cursor = _clampCursor(widget.cursor);
      final Offset caret = fullPainter.getOffsetForCaret(
        TextPosition(offset: cursor),
        Rect.zero,
      );
      const double pad = 12;
      final double current = position.pixels;
      final double leftEdge = current + pad;
      final double rightEdge = current + viewport - pad;
      double target = current;
      if (caret.dx < leftEdge) {
        target = (caret.dx - pad).clamp(0.0, maxScroll);
      } else if (caret.dx > rightEdge) {
        target = (caret.dx - viewport + pad).clamp(0.0, maxScroll);
      }
      if ((position.pixels - target).abs() > 0.5) {
        _scrollController.jumpTo(target);
      }
      _updateScrollVisualState();
    });
  }

  void _ensureFocusAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isActive) return;
      if (!_focusNode.hasFocus) {
        FocusScope.of(context).requestFocus(_focusNode);
      }
    });
  }

  void _handleScrollChanged() => _updateScrollVisualState();

  void _syncScrollVisualStateAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateScrollVisualState();
    });
  }

  void _updateScrollVisualState() {
    if (!_scrollController.hasClients) return;
    final ScrollPosition position = _scrollController.position;
    final double max = position.maxScrollExtent;
    final double offset = position.pixels;
    final bool canScroll = max > 0.5;
    final bool hasHiddenLeft = canScroll && offset > 0.5;
    final bool hasHiddenRight = canScroll && offset < max - 0.5;
    final double ratio = canScroll ? (offset / max).clamp(0.0, 1.0) : 0;
    if (_canScroll == canScroll &&
        _hasHiddenLeft == hasHiddenLeft &&
        _hasHiddenRight == hasHiddenRight &&
        (_scrollRatio - ratio).abs() < 0.001) {
      return;
    }
    setState(() {
      _canScroll = canScroll;
      _hasHiddenLeft = hasHiddenLeft;
      _hasHiddenRight = hasHiddenRight;
      _scrollRatio = ratio;
    });
  }

  void _jumpToTrackPosition(double localDx, double width) {
    if (!_scrollController.hasClients) return;
    final ScrollPosition position = _scrollController.position;
    final double max = position.maxScrollExtent;
    if (max <= 0 || width <= 0) return;
    final double ratio = (localDx / width).clamp(0.0, 1.0);
    _scrollController.jumpTo(max * ratio);
  }

  void _startInsertedTextHighlight({
    required String oldValue,
    required String newValue,
  }) {
    _highlightRange =
        _computeInsertedRange(oldValue: oldValue, newValue: newValue);
    if (_highlightRange == null) {
      _controller.setHighlight(null, null);
      return;
    }
    _insertAnimation.forward(from: 0);
  }

  void _applyHighlightFrame() {
    final TextRange? range = _highlightRange;
    if (range == null) return;
    final double raw = _insertAnimation.value;
    final double fade = ((raw - 0.35) / 0.65).clamp(0.0, 1.0);
    final double t = Curves.easeOutCubic.transform(fade);
    const Color base = WearColors.textDefault;
    final Color accent = Color.lerp(WearColors.red1, Colors.black, 0.18)!;
    final Color animated = Color.lerp(accent, base, t)!;
    _controller.setHighlight(range, animated);
    if (_insertAnimation.status == AnimationStatus.completed) {
      _controller.setHighlight(null, null);
      _highlightRange = null;
    }
  }

  TextRange? _computeInsertedRange({
    required String oldValue,
    required String newValue,
  }) {
    if (newValue.isEmpty || oldValue == newValue) return null;

    int prefix = 0;
    final int minLen =
        oldValue.length < newValue.length ? oldValue.length : newValue.length;
    while (prefix < minLen &&
        oldValue.codeUnitAt(prefix) == newValue.codeUnitAt(prefix)) {
      prefix++;
    }

    int suffix = 0;
    while (suffix < (oldValue.length - prefix) &&
        suffix < (newValue.length - prefix) &&
        oldValue.codeUnitAt(oldValue.length - 1 - suffix) ==
            newValue.codeUnitAt(newValue.length - 1 - suffix)) {
      suffix++;
    }

    final int start = prefix;
    final int end = newValue.length - suffix;
    if (end <= start) return null;
    return TextRange(start: start, end: end);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: _codeFieldHorizontalPadding),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _markUserSelectionIntent(),
            child: TextField(
              controller: _controller,
              scrollController: _scrollController,
              focusNode: _focusNode,
              readOnly: true,
              showCursor: true,
              enableInteractiveSelection: true,
              keyboardType: TextInputType.none,
              cursorColor: WearColors.buttonPrimary,
              style:
                  WearTypography.size20.copyWith(color: WearColors.textDefault),
              textAlign: TextAlign.center,
              decoration: const InputDecoration.collapsed(hintText: ' '),
            ),
          ),
          if (_hasHiddenLeft)
            const Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: _EdgeFadeBlur(isLeft: true),
              ),
            ),
          if (_hasHiddenRight)
            const Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: _EdgeFadeBlur(isLeft: false),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: -5,
            child: AnimatedOpacity(
              opacity: _canScroll ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: SizedBox(
                height: 2.2,
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final double width = constraints.maxWidth;
                    final double thumbWidth = (width * 0.22).clamp(16.0, 44.0);
                    final double left =
                        _canScroll ? (width - thumbWidth) * _scrollRatio : 0.0;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (TapDownDetails details) {
                        _jumpToTrackPosition(details.localPosition.dx, width);
                      },
                      onHorizontalDragUpdate: (DragUpdateDetails details) {
                        _jumpToTrackPosition(details.localPosition.dx, width);
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: Stack(
                          children: <Widget>[
                            Container(
                              height: 1.4,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: <Color>[
                                    WearColors.buttonSecondaryPressed,
                                    WearColors.buttonSecondaryPressed
                                        .withValues(alpha: 0.35),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 110),
                              curve: Curves.easeOutCubic,
                              left: left,
                              child: Container(
                                width: thumbWidth,
                                height: 2.2,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: <Color>[
                                      WearColors.red1,
                                      WearColors.red2,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: WearColors.red1.withValues(
                                        alpha: 0.18,
                                      ),
                                      blurRadius: 2.2,
                                      spreadRadius: 0.2,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EdgeFadeBlur extends StatelessWidget {
  const _EdgeFadeBlur({required this.isLeft});

  final bool isLeft;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 1.4, sigmaY: 0.1),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
              end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
              colors: <Color>[
                WearColors.textDefault.withValues(alpha: 0.12),
                WearColors.textDefault.withValues(alpha: 0.06),
                WearColors.white.withValues(alpha: 0),
              ],
              stops: const <double>[0.0, 0.5, 1.0],
            ),
          ),
          child: const SizedBox(width: 12),
        ),
      ),
    );
  }
}

class _HighlightTextController extends TextEditingController {
  TextRange? _highlightRange;
  Color? _highlightColor;

  void setHighlight(TextRange? range, Color? color) {
    _highlightRange = range;
    _highlightColor = color;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final String valueText = text;
    final TextStyle baseStyle = style ?? const TextStyle();
    final TextRange? range = _highlightRange;
    if (range == null || valueText.isEmpty || range.start >= valueText.length) {
      return TextSpan(style: baseStyle, text: valueText);
    }

    final int start = range.start.clamp(0, valueText.length);
    final int end = range.end.clamp(start, valueText.length);
    if (end <= start) {
      return TextSpan(style: baseStyle, text: valueText);
    }

    return TextSpan(
      style: baseStyle,
      children: <InlineSpan>[
        if (start > 0) TextSpan(text: valueText.substring(0, start)),
        TextSpan(
          text: valueText.substring(start, end),
          style: baseStyle.copyWith(color: _highlightColor ?? baseStyle.color),
        ),
        if (end < valueText.length) TextSpan(text: valueText.substring(end)),
      ],
    );
  }
}

class _DigitsKeyboard extends StatelessWidget {
  const _DigitsKeyboard({
    super.key,
    required this.value,
    required this.onDigit,
    required this.onClose,
    required this.onBackspace,
    required this.onSubmit,
  });

  final String value;
  final ValueChanged<int> onDigit;
  final VoidCallback onClose;
  final VoidCallback onBackspace;
  final VoidCallback onSubmit;

  static const double _topKeyW = 62;
  static const double _keyH = 38;
  static const double _bottomKeyW = 48;
  static const double _bottomKeyH = 32;
  static const double _gap = 4;

  static const double _w = _topKeyW * 3 + _gap * 2;
  static const double _h = _keyH * 3 + _bottomKeyH + _gap * 3;

  @override
  Widget build(BuildContext context) {
    final bool has = value.isNotEmpty;

    return SizedBox(
      width: _w,
      height: _h,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _rowDigits(const <int>[1, 2, 3]),
          const SizedBox(height: _gap),
          _rowDigits(const <int>[4, 5, 6]),
          const SizedBox(height: _gap),
          _rowDigits(const <int>[7, 8, 9]),
          const SizedBox(height: _gap),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _bottomIconKey(
                asset: has ? WearImages.clear : WearImages.close,
                onTap: has ? onBackspace : onClose,
                size: has ? _inputIconSize : 24,
              ),
              const SizedBox(width: _gap),
              _bottomDigitKey(0),
              const SizedBox(width: _gap),
              if (has)
                _bottomIconKey(
                  asset: WearImages.ok,
                  onTap: onSubmit,
                  size: _okIconSize,
                )
              else
                const SizedBox(width: _bottomKeyW, height: _bottomKeyH),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rowDigits(List<int> ds) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _digitKey(ds[0]),
        const SizedBox(width: _gap),
        _digitKey(ds[1]),
        const SizedBox(width: _gap),
        _digitKey(ds[2]),
      ],
    );
  }

  Widget _digitKey(int d) {
    return WearKeyButton(
      width: _topKeyW,
      height: _keyH,
      onTap: () => onDigit(d),
      builder: (_, bool pressed) {
        return Text(
          '$d',
          style: WearTypography.lable18.copyWith(
            height: 0,
            color: pressed ? WearColors.buttonPrimary : WearColors.textDefault,
          ),
        );
      },
    );
  }

  Widget _bottomDigitKey(int d) {
    return WearKeyButton(
      width: _bottomKeyW,
      height: _bottomKeyH,
      onTap: () => onDigit(d),
      builder: (_, bool pressed) {
        return Text(
          '$d',
          style: WearTypography.lable18.copyWith(
            height: 0,
            color: pressed ? WearColors.buttonPrimary : WearColors.textDefault,
          ),
        );
      },
    );
  }

  Widget _iconKey({
    required String asset,
    required VoidCallback onTap,
    double size = _inputIconSize,
  }) {
    return WearKeyButton(
      width: _topKeyW,
      height: _keyH,
      padding: const EdgeInsets.all(0),
      onTap: onTap,
      builder: (_, bool pressed) {
        return WearSvgIcon(
          asset,
          size: size,
          color: pressed ? WearColors.buttonPrimary : WearColors.textDefault,
        );
      },
    );
  }

  Widget _bottomIconKey({
    required String asset,
    required VoidCallback onTap,
    required double size,
    double scale = 1,
  }) {
    return WearKeyButton(
      width: _bottomKeyW,
      height: _bottomKeyH,
      backgroundColor: WearColors.white,
      pressedBackgroundColor: WearColors.white,
      padding: const EdgeInsets.all(0),
      onTap: onTap,
      builder: (_, bool pressed) {
        return Transform.scale(
          scale: scale,
          child: WearSvgIcon(
            asset,
            size: size,
            color: pressed ? WearColors.buttonPrimary : WearColors.textDefault,
          ),
        );
      },
    );
  }
}

class _VoiceKeyboard extends StatelessWidget {
  const _VoiceKeyboard({
    super.key,
    required this.value,
    required this.phase,
    required this.level01,
    required this.onClose,
    required this.onRetry,
    required this.onSubmit,
  });

  final String value;
  final WearVoicePhase phase;
  final ValueListenable<double> level01;

  final VoidCallback onClose;
  final VoidCallback onRetry;
  final VoidCallback onSubmit;

  static const double _voiceSmallW = 48;
  static const double _voiceSmallH = 32;

  @override
  Widget build(BuildContext context) {
    final bool has = value.trim().isNotEmpty;
    // print('voice level: ${level01.value}');
    return SizedBox(
      width: 124,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          WearVoiceIndicator(
            phase: phase,
            level01: level01,
            compact: true,
          ),
          const SizedBox(height: 8),
          if (!has)
            WearKeyButton(
              width: _voiceSmallW,
              height: _voiceSmallH,
              onTap: onClose,
              builder: (_, bool pressed) {
                return WearSvgIcon(
                  WearImages.close,
                  size: _inputIconSize,
                  color: pressed
                      ? WearColors.buttonPrimary
                      : WearColors.textDefault,
                );
              },
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                WearKeyButton(
                  width: _voiceSmallW,
                  height: _voiceSmallH,
                  onTap: onRetry,
                  builder: (_, bool pressed) {
                    return WearSvgIcon(
                      WearImages.reTry,
                      size: _inputIconSize,
                      color: pressed
                          ? WearColors.buttonPrimary
                          : WearColors.textDefault,
                    );
                  },
                ),
                const SizedBox(width: 12),
                WearKeyButton(
                  width: _voiceSmallW,
                  height: _voiceSmallH,
                  onTap: onSubmit,
                  builder: (_, bool pressed) {
                    return Transform.scale(
                      scale: _okIconScale,
                      child: WearSvgIcon(
                        WearImages.ok,
                        size: _okIconSize,
                        color: pressed
                            ? WearColors.buttonPrimary
                            : WearColors.textDefault,
                      ),
                    );
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
}
