import 'package:flutter/material.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/wear/wear_glasses_state.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/glasses_preview/glasses_preview_provider.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/glasses_preview/wear_glasses_preview_widget.dart';

class WearGlassesPreviewOverlay extends StatefulWidget {
  const WearGlassesPreviewOverlay({super.key});

  @override
  State<WearGlassesPreviewOverlay> createState() => _WearGlassesPreviewOverlayState();
}

class _WearGlassesPreviewOverlayState extends State<WearGlassesPreviewOverlay> {
  bool _isExpanded = false;
  Offset _position = const Offset(16, 100);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GlassesPreviewNotifier.I,
      builder: (context, _) {
        final state = GlassesPreviewNotifier.I.state;
        return Stack(
          children: <Widget>[
            if (_isExpanded)
              Positioned(
                left: _position.dx,
                top: (_position.dy - 260).clamp(0.0, MediaQuery.of(context).size.height - 260),
                child: _buildPreviewCard(state),
              ),
            Positioned(
              left: _position.dx,
              top: _position.dy,
              child: _buildFloatingButton(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPreviewCard(WearGlassesState state) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.visibility,
                  size: 14,
                  color: Colors.white70,
                ),
                const SizedBox(width: 4),
                Text(
                  'ОЧКИ',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => _isExpanded = false),
                  child: const Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            WearGlassesPreviewWidget(
              state: state,
              width: 200,
              height: 200,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingButton() {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          _position = Offset(
            (_position.dx + details.delta.dx).clamp(0, MediaQuery.of(context).size.width - 60),
            (_position.dy + details.delta.dy).clamp(0, MediaQuery.of(context).size.height - 60),
          );
        });
      },
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              _isExpanded ? Icons.visibility_off : Icons.visibility,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}
