import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_availability_glasses_payloads.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_direct_scan_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_group_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_scaling_list_view.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WearStatusIconReporter.I.send(
        WearAvailabilityGlassesPayloads.interactionTypes(),
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

    return WearScreenScaffold(
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
      ),
    );
  }
}
