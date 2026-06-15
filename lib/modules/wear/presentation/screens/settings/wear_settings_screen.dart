import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
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
      ),
    );
  }
}
