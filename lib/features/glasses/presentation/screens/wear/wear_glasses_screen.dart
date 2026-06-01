import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/wear/wear_glasses_cubit.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/wear/wear_glasses_state.dart';
import 'package:smart_glasses/features/glasses/presentation/widgets/wear/wear_glasses_scaffold.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

class WearGlassesScreen extends StatelessWidget {
  const WearGlassesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WearGlassesCubit, WearGlassesState>(
      builder: (BuildContext context, WearGlassesState state) {
        return WearGlassesScaffold(
          child: Stack(
            children: <Widget>[
              const Align(
                alignment: Alignment.topRight,
                child: _StatusBar(),
              ),
              Center(
                child: SizedBox(
                  height: 340,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _TitleBlock(state: state),
                      const SizedBox(height: 24),
                      Expanded(child: _Body(state: state)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.state});

  final WearGlassesState state;

  @override
  Widget build(BuildContext context) {
    final Color color =
        state.isError ? Colors.redAccent : WearGlassesScaffold.accentColor;
    final bool isList = state.items.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          state.title,
          style: TextStyle(
            color: color,
            fontSize: isList ? 36 : 40,
            height: isList ? 1.11 : 1.4,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
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
    if (state.items.isNotEmpty) {
      return _WearList(state: state);
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
          Column(
            children: <Widget>[
              for (int i = 0; i < visible.length; i++)
                Padding(
                  padding:
                      EdgeInsets.only(bottom: i == visible.length - 1 ? 0 : 4),
                  child: _WearListItem(
                    text: visible[i],
                    selected: i == state.selectedIndex,
                  ),
                ),
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

class _MainStatus extends StatelessWidget {
  const _MainStatus({required this.state});

  final WearGlassesState state;

  @override
  Widget build(BuildContext context) {
    final Color color =
        state.isError ? Colors.redAccent : WearGlassesScaffold.accentColor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (state.isLoading) ...<Widget>[
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: color,
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
      ..moveTo(size.width * 0.20, size.height * 0.50)
      ..lineTo(size.width * 0.45, size.height * 0.75)
      ..lineTo(size.width * 0.82, size.height * 0.25);
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (state.primaryAction != null) _ActionPill(state.primaryAction!),
        if (state.secondaryAction != null) ...<Widget>[
          const SizedBox(width: 12),
          _ActionPill(state.secondaryAction!, isSecondary: true),
        ],
      ],
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill(this.text, {this.isSecondary = false});

  final String text;
  final bool isSecondary;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color:
            isSecondary ? Colors.transparent : WearGlassesScaffold.accentColor,
        border: Border.all(color: WearGlassesScaffold.accentColor, width: 2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        child: Text(
          text,
          style: TextStyle(
            color: isSecondary
                ? WearGlassesScaffold.accentColor
                : WearGlassesScaffold.designBackgroundColor,
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
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.wifi, size: 20, color: Colors.black),
        SizedBox(width: 12),
        Icon(Icons.battery_full, size: 20, color: Colors.black),
      ],
    );
  }
}
