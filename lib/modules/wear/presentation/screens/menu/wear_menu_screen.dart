import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/help/wear_help_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/printers/wear_printer_select_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/settings/wear_settings_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_scaling_list_view.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/services/wear_status_icon_reporter.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearMenuScreen extends StatefulWidget {
  const WearMenuScreen({super.key});

  static const String route = '/wear_menu';

  @override
  State<WearMenuScreen> createState() => _WearMenuScreenState();
}

class _WearMenuScreenState extends State<WearMenuScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WearStatusIconReporter.I.send(WearGlassesPayload.menu());
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
          'Меню',
          style: WearTypography.lable15,
          textAlign: TextAlign.center,
        ),
      ),
      WearPill(
        title: 'Печать ценника',
        onTap: () => context.push(WearPrinterSelectScreen.route),
      ),
      WearPill(
        title: 'Справка',
        onTap: () => context.push(WearHelpScreen.route),
      ),
      WearPill(
        title: 'Настройки',
        icon: WearImages.gear,
        onTap: () => context.push(WearSettingsScreen.route),
      ),
      const SizedBox(
        height: 50,
      )
    ];

    return WearScreenScaffold(
      scrollController: _scroll,
      child: WearScalingListView(
        controller: _scroll,
        itemCount: items.length,
        itemExtent: 56,
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 4.5),
        edgeFractionTop: 0.06,
        edgeFractionBottom: 0.14,
        minScale: 0.72,
        minOpacity: 0.30,
        baseSideInset: 10,
        extraSideInset: 30,
        itemBuilder: (BuildContext context, int i) => items[i],
      ),
    );
  }
}
