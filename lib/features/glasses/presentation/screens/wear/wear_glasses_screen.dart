import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/wear/wear_glasses_cubit.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/wear/wear_glasses_state.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/wear/wear_voice_overlay_cubit.dart';
import 'package:smart_glasses/features/glasses/presentation/widgets/wear/wear_glasses_scaffold.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';

class WearGlassesScreen extends StatefulWidget {
  const WearGlassesScreen({super.key});

  @override
  State<WearGlassesScreen> createState() => _WearGlassesScreenState();
}

class _WearGlassesScreenState extends State<WearGlassesScreen> {
  int _scheduledUpdateId = -1;

  void _logMenuFrame(WearGlassesState state) {
    if (state.screenType != WearGlassesScreenType.menu ||
        state.updateId == _scheduledUpdateId) {
      return;
    }
    _scheduledUpdateId = state.updateId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final int renderedAtMillis = DateTime.now().millisecondsSinceEpoch;
      // ignore: avoid_print
      print(
        '[WearGlassesScreen] menu frame rendered update#${state.updateId} '
        'selectedIndex=${state.selectedIndex} '
        'payloadReceivedAt=${state.payloadReceivedAtMillis} '
        'receiveToFrameMs='
        '${renderedAtMillis - state.payloadReceivedAtMillis} '
        'at=$renderedAtMillis',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WearVoiceOverlayCubit, WearVoiceOverlayState>(
      builder: (BuildContext context, WearVoiceOverlayState overlay) {
        return BlocBuilder<WearGlassesCubit, WearGlassesState>(
          builder: (BuildContext context, WearGlassesState state) {
            _logMenuFrame(state);
            return WearGlassesScaffold(
              child: Stack(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        children: <Widget>[
                          _TitleBlock(state: state),
                          const SizedBox(height: 12),
                          Expanded(child: _Body(state: state)),
                        ],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8, right: 8),
                      child: _StatusBar(state: state),
                    ),
                  ),
                  if (overlay.visible) _VoiceOverlay(overlay: overlay),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _VoiceOverlay extends StatelessWidget {
  const _VoiceOverlay({required this.overlay});

  final WearVoiceOverlayState overlay;

  @override
  Widget build(BuildContext context) {
    final String message =
        overlay.message ?? 'Переподключаем\nголосовое управление';
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xE6000000),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (overlay.isError)
                const Icon(Icons.error_outline,
                    color: Colors.redAccent, size: 56)
              else
                const SizedBox(
                  width: 52,
                  height: 52,
                  child: CircularProgressIndicator(
                    color: WearGlassesScaffold.accentColor,
                    strokeWidth: 5,
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: WearGlassesScaffold.accentColor,
                  fontSize: 28,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.state});

  final WearGlassesState state;

  @override
  Widget build(BuildContext context) {
    const Color color = WearGlassesScaffold.accentColor;
    final bool isList = state.items.isNotEmpty &&
        state.screenType != WearGlassesScreenType.continueScan;
    final bool useDesignTitle =
        state.screenType == WearGlassesScreenType.availability ||
            state.screenType == WearGlassesScreenType.help;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          state.title,
          style: TextStyle(
            color: color,
            fontSize: useDesignTitle || isList ? 36 : 40,
            height: useDesignTitle || isList ? 1.11 : 1.4,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        if (state.subtitle != null &&
            state.subtitle!.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            state.subtitle!,
            style: TextStyle(
              color: color,
              fontSize: 20,
              height: 1.4,
              fontWeight: FontWeight.w400,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state});

  final WearGlassesState state;

  @override
  Widget build(BuildContext context) {
    if (state.screenType == WearGlassesScreenType.continueScan) {
      return Center(
        child: _Actions(state: state),
      );
    }

    if (state.items.isNotEmpty) {
      if (state.screenType == WearGlassesScreenType.help) {
        return _HelpBody(state: state);
      }
      return _WearList(state: state);
    }
    if (state.screenType == WearGlassesScreenType.availability) {
      return _AvailabilityBody(state: state);
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (state.statusText != null && state.statusText!.trim().isNotEmpty)
            _MainStatus(state: state),
          if (state.primaryAction != null ||
              state.secondaryAction != null) ...<Widget>[
            const SizedBox(height: 26),
            _Actions(state: state),
          ],
        ],
      ),
    );
  }
}

class _AvailabilityBody extends StatelessWidget {
  const _AvailabilityBody({required this.state});

  final WearGlassesState state;

  @override
  Widget build(BuildContext context) {
    final bool hasStatus =
        state.statusText != null && state.statusText!.trim().isNotEmpty;
    final bool hasActions =
        state.primaryAction != null || state.secondaryAction != null;
    return SizedBox(
      width: state.checkLines.isEmpty ? 520 : 577,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (state.bodyLines.isNotEmpty || state.checkLines.isNotEmpty)
            state.checkLines.isEmpty
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (final String line in state.bodyLines)
                        _InfoLine(line),
                    ],
                  )
                : _AvailabilityDetails(state: state),
          if (hasStatus) ...<Widget>[
            if (state.bodyLines.isNotEmpty || state.checkLines.isNotEmpty)
              const SizedBox(height: 18),
            _MainStatus(state: state),
          ],
          if (state.footerText != null &&
              state.footerText!.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              state.footerText!,
              style: const TextStyle(
                color: WearGlassesScaffold.accentColor,
                fontSize: 15,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
          if (hasActions) ...<Widget>[
            const SizedBox(height: 26),
            _Actions(state: state),
          ],
        ],
      ),
    );
  }
}

class _AvailabilityDetails extends StatelessWidget {
  const _AvailabilityDetails({required this.state});

  final WearGlassesState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final String line in state.bodyLines) _DetailLine(line),
            ],
          ),
        ),
        const SizedBox(width: 56),
        SizedBox(
          width: 166,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const _DetailLine('Проверки:'),
              const SizedBox(height: 6),
              for (final String line in state.checkLines) _CheckLine(line),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          color: WearGlassesScaffold.accentColor,
          fontSize: 20,
          height: 1.4,
          fontWeight: FontWeight.w400,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _CheckLine extends StatelessWidget {
  const _CheckLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: _CheckStatusMark(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: WearGlassesScaffold.accentColor,
                fontSize: 18,
                height: 1.35,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckStatusMark extends StatelessWidget {
  const _CheckStatusMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CustomPaint(
        painter: _CheckStatusMarkPainter(),
      ),
    );
  }
}

class _CheckStatusMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = WearGlassesScaffold.accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width * 0.38,
      paint,
    );
    final Path path = Path()
      ..moveTo(size.width * 0.34, size.height * 0.50)
      ..lineTo(size.width * 0.45, size.height * 0.61)
      ..lineTo(size.width * 0.66, size.height * 0.39);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: WearGlassesScaffold.accentColor,
          fontSize: 20,
          height: 1.35,
          fontWeight: FontWeight.w400,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _HelpBody extends StatelessWidget {
  const _HelpBody({required this.state});

  final WearGlassesState state;

  @override
  Widget build(BuildContext context) {
    const Color color = WearGlassesScaffold.accentColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < state.items.length; i++) ...<Widget>[
          if (i > 0) const Spacer(),
          Text(
            state.items[i],
            style: TextStyle(
              color: color,
              fontSize: 18,
              height: 1.3,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
        if (state.primaryAction != null ||
            state.secondaryAction != null) ...<Widget>[
          const Spacer(),
          _Actions(state: state),
        ],
      ],
    );
  }
}

class _WearList extends StatelessWidget {
  const _WearList({required this.state});

  final WearGlassesState state;

  @override
  Widget build(BuildContext context) {
    final List<String> visible = state.items.take(4).toList(growable: false);
    final bool showPageText =
        state.pageText != null && state.pageText!.trim().isNotEmpty;
    return SizedBox(
      width: 403,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  children: <Widget>[
                    for (int i = 0; i < visible.length; i++)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: i == visible.length - 1 ? 0 : 4,
                        ),
                        child: _WearListItem(
                          text: visible[i],
                          selected: i == state.selectedIndex,
                        ),
                      ),
                  ],
                ),
              ),
              if (showPageText) ...<Widget>[
                const SizedBox(width: 8),
                const _ListScrollBar(),
              ],
            ],
          ),
          if (showPageText) ...<Widget>[
            const SizedBox(height: 8),
            _PageText(state.pageText!),
          ],
        ],
      ),
    );
  }
}

class _ListScrollBar extends StatelessWidget {
  const _ListScrollBar();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 16,
      height: 188,
      child: Column(
        children: <Widget>[
          _ScrollArrow(up: true),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.topCenter,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: WearGlassesScaffold.accentColor,
                    borderRadius: BorderRadius.all(Radius.circular(2)),
                  ),
                  child: SizedBox(width: 4, height: 71),
                ),
              ),
            ),
          ),
          _ScrollArrow(up: false),
        ],
      ),
    );
  }
}

class _ScrollArrow extends StatelessWidget {
  const _ScrollArrow({required this.up});

  final bool up;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: CustomPaint(
        painter: _ScrollArrowPainter(up: up),
      ),
    );
  }
}

class _ScrollArrowPainter extends CustomPainter {
  const _ScrollArrowPainter({required this.up});

  final bool up;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = WearGlassesScaffold.accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final double top = up ? size.height * 0.62 : size.height * 0.38;
    final double bottom = up ? size.height * 0.38 : size.height * 0.62;
    final Path path = Path()
      ..moveTo(size.width * 0.32, top)
      ..lineTo(size.width * 0.50, bottom)
      ..lineTo(size.width * 0.68, top);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ScrollArrowPainter oldDelegate) {
    return oldDelegate.up != up;
  }
}

class _MainStatus extends StatelessWidget {
  const _MainStatus({required this.state});

  final WearGlassesState state;

  @override
  Widget build(BuildContext context) {
    const Color color = WearGlassesScaffold.accentColor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (state.statusIcon != null &&
                state.statusIcon!.trim().isNotEmpty) ...<Widget>[
              SvgPicture.asset(
                state.statusIcon!,
                width: 20,
                height: 20,
                colorFilter: const ColorFilter.mode(
                  WearGlassesScaffold.accentColor,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                _designStatusText(state),
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  height: 1.4,
                  fontWeight: FontWeight.w400,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        if (state.isLoading) ...<Widget>[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              width: 205,
              height: 4,
              child: LinearProgressIndicator(
                backgroundColor:
                    WearGlassesScaffold.accentColor.withValues(alpha: 0.30),
                color: color,
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _designStatusText(WearGlassesState state) {
    if (state.statusText == null) return '';
    final String statusText = state.statusText!.trim();
    if (statusText.endsWith('...')) return statusText;
    switch (state.phase) {
      case WearGlassesPhase.scanning:
      case WearGlassesPhase.recognizing:
      case WearGlassesPhase.loading:
        return '$statusText...';
      case WearGlassesPhase.idle:
      case WearGlassesPhase.success:
      case WearGlassesPhase.error:
        return statusText;
    }
  }
}

class _WearListItem extends StatelessWidget {
  const _WearListItem({
    required this.text,
    required this.selected,
  });

  final String text;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected
            ? WearGlassesScaffold.accentColor.withValues(alpha: 0.05)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: selected
            ? Border.all(
                color: WearGlassesScaffold.accentColor,
                width: 1,
              )
            : null,
      ),
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: <Widget>[
              if (selected) ...<Widget>[
                const _SelectionMarker(),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : WearGlassesScaffold.accentColor,
                    fontSize: 20,
                    height: 1.4,
                    fontWeight: FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionMarker extends StatelessWidget {
  const _SelectionMarker();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(
        painter: _SelectionMarkerPainter(),
      ),
    );
  }
}

class _SelectionMarkerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = WearGlassesScaffold.accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Path path = Path()
      ..moveTo(size.width * 0.38, size.height * 0.25)
      ..lineTo(size.width * 0.68, size.height * 0.50)
      ..lineTo(size.width * 0.38, size.height * 0.75);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Actions extends StatelessWidget {
  const _Actions({required this.state});

  final WearGlassesState state;

  @override
  Widget build(BuildContext context) {
    final bool isContinueScan =
        state.screenType == WearGlassesScreenType.continueScan;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (state.primaryAction != null)
          _ActionPill(
            state.primaryAction!,
            isSecondary: state.screenType == WearGlassesScreenType.help,
            isSelected: isContinueScan ? state.selectedIndex == 0 : null,
          ),
        if (state.secondaryAction != null) ...<Widget>[
          const SizedBox(width: 12),
          _ActionPill(
            state.secondaryAction!,
            isSecondary: true,
            isSelected: isContinueScan ? state.selectedIndex == 1 : null,
          ),
        ],
      ],
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill(
    this.text, {
    this.isSecondary = false,
    this.isSelected,
  });

  final String text;
  final bool isSecondary;
  final bool? isSelected;

  @override
  Widget build(BuildContext context) {
    final bool selected = isSelected ?? !isSecondary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? WearGlassesScaffold.accentColor : Colors.transparent,
        border: Border.all(color: WearGlassesScaffold.accentColor, width: 2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
        child: Text(
          text,
          style: TextStyle(
            color: selected
                ? WearGlassesScaffold.designBackgroundColor
                : WearGlassesScaffold.accentColor,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _PageText extends StatelessWidget {
  const _PageText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: WearGlassesScaffold.accentColor,
        fontSize: 15,
        height: 1.87,
      ),
      textAlign: TextAlign.right,
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.state});

  final WearGlassesState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (state.showWifiIcon)
          _GlassesCrossableIcon(
            available: state.wifiAvailable,
            child: CustomPaint(
              size: const Size.square(20),
              painter: _GlassesWifiPainter(level: state.wifiLevel),
            ),
          ),
        if (state.showWifiIcon && state.showPrinterIcon)
          const SizedBox(width: 12),
        if (state.showPrinterIcon)
          _GlassesCrossableIcon(
            available: state.printerAvailable,
            child: SvgPicture.asset(
              WearImages.printer,
              width: 20,
              height: 20,
              colorFilter: const ColorFilter.mode(
                WearGlassesScaffold.accentColor,
                BlendMode.srcIn,
              ),
            ),
          ),
      ],
    );
  }
}

class _GlassesCrossableIcon extends StatelessWidget {
  const _GlassesCrossableIcon({
    required this.available,
    required this.child,
  });

  final bool available;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          child,
          if (!available)
            Transform.rotate(
              angle: -0.75,
              child: Container(
                width: 24,
                height: 2.2,
                decoration: BoxDecoration(
                  color: WearGlassesScaffold.accentColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GlassesWifiPainter extends CustomPainter {
  const _GlassesWifiPainter({required this.level});

  final int level;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = WearGlassesScaffold.accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final Offset center = Offset(size.width / 2, size.height * 0.82);
    final int visibleLevel = level.clamp(1, 3);

    if (visibleLevel >= 3) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 12),
        -2.38,
        1.62,
        false,
        paint,
      );
    }
    if (visibleLevel >= 2) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 8),
        -2.28,
        1.42,
        false,
        paint,
      );
    }
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 4),
      -2.08,
      1.02,
      false,
      paint,
    );
    canvas.drawCircle(
      center,
      1.7,
      Paint()..color = WearGlassesScaffold.accentColor,
    );
  }

  @override
  bool shouldRepaint(covariant _GlassesWifiPainter oldDelegate) {
    return oldDelegate.level != level;
  }
}
