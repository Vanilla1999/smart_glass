import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/config/wear_session.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_fill_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/main/wear_main_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/settings/db_settings_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_scaling_list_view.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearSettingsScreen extends ConsumerStatefulWidget {
  const WearSettingsScreen({super.key});

  static const String route = '/wear_settings';

  @override
  ConsumerState<WearSettingsScreen> createState() => _WearSettingsScreenState();
}

class _WearSettingsScreenState extends ConsumerState<WearSettingsScreen> {
  final ScrollController _scroll = ScrollController();
  int _focusedIndex = 0;
  static const int _itemCount = 4;

  @override
  void initState() {
    super.initState();
    WearDependencies.I.wearFlowController.enterScreen(WearScreenId.settings);
    WearDependencies.I.wearFlowController.registerScreenActions(
      WearScreenId.settings,
      WearScreenActionHandler(
        onUp: _onVoiceUp,
        onDown: _onVoiceDown,
        onSelect: _onVoiceSelect,
        onConnectScanner: _connectRingScanner,
        onSwitchUser: _switchUser,
        onOpenDbSettings: _switchDB,
        onFillDatabase: _openAvailabilityFill,
      ),
    );
  }

  @override
  void dispose() {
    WearDependencies.I.wearFlowController.unregisterScreenActions(
      WearScreenId.settings,
    );
    _scroll.dispose();
    super.dispose();
  }

  void _onVoiceUp() {
    if (_focusedIndex <= 0) return;
    setState(() => _focusedIndex--);
    _scrollToFocused();
  }

  void _onVoiceDown() {
    if (_focusedIndex >= _itemCount - 1) return;
    setState(() => _focusedIndex++);
    _scrollToFocused();
  }

  void _onVoiceSelect() {
    switch (_focusedIndex) {
      case 0:
        _connectRingScanner();
        break;
      case 1:
        _switchUser();
        break;
      case 2:
        _switchDB();
        break;
      case 3:
        _openAvailabilityFill();
        break;
    }
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

  Future<void> _switchUser() async {
    WearSession.clear();
    if (!mounted) return;
    context.go(WearMainScreen.route);
  }

  Future<void> _switchDB() async {
    if (!mounted) return;
    context.go(DBSettingsScreen.route);
  }

  Future<void> _openAvailabilityFill() async {
    if (!mounted) return;
    context.push(WearAvailabilityFillScreen.route);
  }

  void _connectRingScanner() {
    // TODO: remove stub dep
    // ref.read(bluetoothNotifierProvider.notifier).showBluetoothDialog();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> items = <Widget>[
      Align(
        alignment: Alignment.topCenter,
        child: Text(
          'Настройки',
          style: WearTypography.lable15,
          textAlign: TextAlign.center,
        ),
      ),
      WearPill(
        title: 'Подключить кольцо',
        icon: WearImages.barcode,
        onTap: _connectRingScanner,
      ),
      WearPill(
        title: 'Сменить пользователя',
        icon: WearImages.userSwitch,
        onTap: _switchUser,
      ),
      WearPill(
        title: 'Настройки БД',
        icon: WearImages.userSwitch,
        onTap: _switchDB,
      ),
      WearPill(
        title: 'Наполнить базу',
        icon: WearImages.database,
        onTap: _openAvailabilityFill,
      ),
      const SizedBox(
        height: 50,
      )
    ];

    return WearScreenScaffold(
      showHomeButton: true,
      scrollController: _scroll,
      child: WearScalingListView(
        controller: _scroll,
        itemCount: items.length,
        itemExtent: 56,
        padding: const EdgeInsets.fromLTRB(0, 40, 0, 4.5),
        edgeFractionTop: 0.0,
        edgeFractionBottom: 0.14,
        baseSideInset: 10,
        extraSideInset: 34,
        itemBuilder: (BuildContext context, int i) => items[i],
        onFocusChanged: (int listIndex) {
          final int itemIndex = (listIndex - 1).clamp(0, _itemCount - 1);
          if (itemIndex == _focusedIndex) return;
          setState(() => _focusedIndex = itemIndex);
        },
      ),
    );
  }
}
