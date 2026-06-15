import 'package:flutter/material.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/wear/wear_glasses_state.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

class WearGlassesPreviewWidget extends StatelessWidget {
  const WearGlassesPreviewWidget({
    super.key,
    required this.state,
    this.width = 240,
    this.height = 240,
  });

  final WearGlassesState state;
  final double width;
  final double height;

  static const Color _accentColor = Color(0xFF1A1A1A);
  static const Color _bgColor = Color(0xFFF5F5F5);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _accentColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          children: <Widget>[
            _buildStatusBar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  children: <Widget>[
                    _buildTitle(),
                    const SizedBox(height: 8),
                    Expanded(child: _buildBody()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: _bgColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          if (state.showWifiIcon) _buildWifiIcon(),
          if (state.showPrinterIcon) ...<Widget>[
            const SizedBox(width: 8),
            _buildPrinterIcon(),
          ],
        ],
      ),
    );
  }

  Widget _buildWifiIcon() {
    final color = state.wifiAvailable ? _accentColor : _accentColor.withValues(alpha: 0.4);
    return Icon(Icons.wifi, size: 14, color: color);
  }

  Widget _buildPrinterIcon() {
    final color = state.printerAvailable ? _accentColor : _accentColor.withValues(alpha: 0.4);
    return Icon(Icons.print, size: 14, color: color);
  }

  Widget _buildTitle() {
    return Column(
      children: <Widget>[
        Text(
          state.title,
          style: const TextStyle(
            color: _accentColor,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (state.subtitle != null && state.subtitle!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            state.subtitle!,
            style: TextStyle(
              color: _accentColor.withValues(alpha: 0.8),
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _buildBody() {
    if (state.items.isNotEmpty) {
      return _buildList();
    }
    return _buildStatus();
  }

  Widget _buildList() {
    final visibleItems = state.items.take(3).toList();
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: visibleItems.length,
      itemBuilder: (context, index) {
        final isSelected = index == state.selectedIndex;
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? _accentColor.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: isSelected ? Border.all(color: _accentColor, width: 1) : null,
          ),
          child: Row(
            children: <Widget>[
              if (isSelected) ...<Widget>[
                Icon(Icons.check, size: 12, color: _accentColor),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  visibleItems[index],
                  style: TextStyle(
                    color: isSelected ? _accentColor : _accentColor.withValues(alpha: 0.8),
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatus() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (state.statusText != null && state.statusText!.isNotEmpty) ...<Widget>[
          Text(
            _getStatusText(),
            style: const TextStyle(
              color: _accentColor,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (state.isLoading) ...<Widget>[
            const SizedBox(height: 8),
            SizedBox(
              width: 80,
              child: LinearProgressIndicator(
                backgroundColor: _accentColor.withValues(alpha: 0.2),
                color: _accentColor,
                minHeight: 2,
              ),
            ),
          ],
        ],
        if (state.primaryAction != null) ...<Widget>[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _accentColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              state.primaryAction!,
              style: const TextStyle(
                color: _bgColor,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        if (state.screenType == WearGlassesScreenType.auth) ...<Widget>[
          const SizedBox(height: 8),
          Icon(
            Icons.qr_code_scanner,
            size: 32,
            color: _accentColor.withValues(alpha: 0.6),
          ),
        ],
      ],
    );
  }

  String _getStatusText() {
    if (state.statusText == null) return '';
    final text = state.statusText!.trim();
    switch (state.phase) {
      case WearGlassesPhase.scanning:
      case WearGlassesPhase.recognizing:
      case WearGlassesPhase.loading:
        return '$text...';
      default:
        return text;
    }
  }
}
