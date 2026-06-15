import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_availability_glasses_payloads.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_direct_scan_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_group_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_scaling_list_view.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_voice_command_listener.dart';
import 'package:smart_glasses/modules/wear/services/wear_status_icon_reporter.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearAvailabilityInteractionScreen extends StatefulWidget {
  const WearAvailabilityInteractionScreen({super.key});

  static const String route = '/wear_availability_interaction';

  @override
  State<WearAvailabilityInteractionScreen> createState() =>
      _WearAvailabilityInteractionScreenState();
}

class _WearAvailabilityInteractionScreenState
    extends State<WearAvailabilityInteractionScreen> {
  final ScrollController _scroll = ScrollController();
  int _focusedIndex = 0;
  static const int _itemCount = 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WearStatusIconReporter.I.send(
        WearAvailabilityGlassesPayloads.interactionTypes(
          selectedIndex: _focusedIndex,
        ),
      );
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> items = <Widget>[
      Align(
        alignment: Alignment.topCenter,
        child: Text(
          'Тип взаимодействия',
          style: WearTypography.lable,
          textAlign: TextAlign.center,
        ),
      ),
      WearPill(
        title: 'Список',
        icon: WearImages.database,
        onTap: () => context.push(WearAvailabilityGroupScreen.route),
      ),
      WearPill(
        title: 'Прямое сканирование',
        icon: WearImages.barcode,
        onTap: () => context.push(WearAvailabilityDirectScanScreen.route),
      ),
      const SizedBox(height: 50),
    ];

    return WearVoiceCommandListener(
      onUp: _onVoiceUp,
      onDown: _onVoiceDown,
      onSelect: _onVoiceSelect,
      child: WearScreenScaffold(
        showHomeButton: true,
        scrollController: _scroll,
        child: WearScalingListView(
          controller: _scroll,
          itemCount: items.length,
          itemExtent: 56,
          padding: const EdgeInsets.fromLTRB(0, 40, 0, 4.5),
          edgeFractionTop: 0.0,
          minScale: 0.68,
          minOpacity: 0.26,
          extraSideInset: 40,
          itemBuilder: (BuildContext context, int i) => items[i],
          onFocusChanged: (int listIndex) {
            final int itemIndex = (listIndex - 1).clamp(0, _itemCount - 1);
            if (itemIndex == _focusedIndex) return;
            _focusedIndex = itemIndex;
            _sendGlassesFocus();
          },
        ),
      ),
    );
  }

  void _onVoiceUp() {
    if (_focusedIndex <= 0) return;
    _focusedIndex--;
    _scrollToFocused();
    _sendGlassesFocus();
  }

  void _onVoiceDown() {
    if (_focusedIndex >= _itemCount - 1) return;
    _focusedIndex++;
    _scrollToFocused();
    _sendGlassesFocus();
  }

  void _onVoiceSelect() {
    if (_focusedIndex == 0) {
      context.push(WearAvailabilityGroupScreen.route);
      return;
    }
    context.push(WearAvailabilityDirectScanScreen.route);
  }

  void _scrollToFocused() {
    if (!_scroll.hasClients) return;
    final double target = ((_focusedIndex + 1) * 56.0).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  void _sendGlassesFocus() {
    WearStatusIconReporter.I.sendFast(
      WearAvailabilityGlassesPayloads.interactionTypes(
        selectedIndex: _focusedIndex,
      ),
    );
  }
}
