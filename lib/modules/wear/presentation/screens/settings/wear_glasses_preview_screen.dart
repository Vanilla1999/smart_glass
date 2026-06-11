import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_glasses/features/glasses/presentation/cubit/wear/wear_glasses_cubit.dart';
import 'package:smart_glasses/features/glasses/presentation/screens/wear/wear_glasses_screen.dart';
import 'package:smart_glasses/features/glasses/presentation/widgets/wear/wear_glasses_scaffold.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_flow_state.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_availability_glasses_payloads.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/services/wear_status_icon_reporter.dart';

class WearGlassesPreviewScreen extends StatefulWidget {
  const WearGlassesPreviewScreen({super.key});

  static const String route = '/wear_glasses_preview';

  @override
  State<WearGlassesPreviewScreen> createState() =>
      _WearGlassesPreviewScreenState();
}

class _WearGlassesPreviewScreenState extends State<WearGlassesPreviewScreen> {
  late final WearGlassesCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = WearGlassesCubit();
    _showCurrent();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFEFEF),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double scale = math.min(
                    constraints.maxWidth / WearGlassesScaffold.designWidth,
                    constraints.maxHeight / WearGlassesScaffold.designHeight,
                  );
                  return Center(
                    child: SizedBox(
                      width: WearGlassesScaffold.designWidth * scale,
                      height: WearGlassesScaffold.designHeight * scale,
                      child: Transform.scale(
                        scale: scale,
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: WearGlassesScaffold.designWidth,
                          height: WearGlassesScaffold.designHeight,
                          child: BlocProvider<WearGlassesCubit>.value(
                            value: _cubit,
                            child: const WearGlassesScreen(),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  SizedBox(
                    width: 132,
                    child: WearPill(
                      title: 'Текущий',
                      onTap: _showCurrent,
                    ),
                  ),
                  SizedBox(
                    width: 132,
                    child: WearPill(
                      title: 'Меню',
                      onTap: () => _update(WearGlassesPayload.menu()),
                    ),
                  ),
                  SizedBox(
                    width: 132,
                    child: WearPill(
                      title: 'Доступность',
                      onTap: () => _update(
                        WearAvailabilityGlassesPayloads.fromFlow(
                          _sampleFlow(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCurrent() {
    _update(
      WearStatusIconReporter.I.lastPayload ??
          WearAvailabilityGlassesPayloads.fromFlow(_sampleFlow()),
    );
  }

  void _update(WearGlassesPayload payload) {
    _cubit.updateFromPayload(payload.toJson());
  }

  WearAvailabilityFlowState _sampleFlow() {
    return const WearAvailabilityFlowState(
      step: WearAvailabilityFlowStep.productQuestion,
      check: WearAvailabilityProductCheck(
        product: WearAvailabilityProduct(
          id: 1002001,
          groupId: 10,
          name: 'Молоко питьевое 3,2% 930 мл',
          code: '1002001',
          barcodes: <String>['4600001002001'],
          priceTagBarcodes: <String>['2201002001'],
          price: 89.90,
          loyaltyPrice: 79.90,
          rest: 12,
          checkPrice: true,
          photoControl: true,
          unpackaged: false,
          priceTagActual: false,
        ),
      ),
      message: 'Товар есть на полке?',
    );
  }
}
