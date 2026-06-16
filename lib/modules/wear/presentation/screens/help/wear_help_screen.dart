import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/services/wear_status_icon_reporter.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearHelpScreen extends StatefulWidget {
  const WearHelpScreen({super.key});

  static const String route = '/wear_help';

  @override
  State<WearHelpScreen> createState() => _WearHelpScreenState();
}

class _WearHelpScreenState extends State<WearHelpScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WearDependencies.I.wearFlowController.enterScreen(WearScreenId.help);
    WearDependencies.I.wearFlowController.registerScreenActions(
      WearScreenId.help,
      WearScreenActionHandler(onSelect: _onVoiceSelect),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WearStatusIconReporter.I.send(WearGlassesPayload.help());
    });
  }

  @override
  void dispose() {
    WearDependencies.I.wearFlowController.unregisterScreenActions(
      WearScreenId.help,
    );
    _scroll.dispose();
    super.dispose();
  }

  void _onVoiceSelect() {
    WearStatusIconReporter.I.send(WearGlassesPayload.menu());
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return WearScreenScaffold(
      scrollController: _scroll,
      showStatusBar: false,
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
        children: <Widget>[
          Text(
            'Справка',
            style: WearTypography.lable,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const _HelpSection(
            title: 'Дистанция сканирования',
            body: 'до 50 см',
          ),
          const SizedBox(height: 8),
          const _HelpSection(
            title: 'Голосовые команды',
            body: '«Вверх», «Вниз», «Выбрать», «Назад», «Домой»',
          ),
          const SizedBox(height: 8),
          const _HelpSection(
            title: 'Кнопки',
            body:
                '↑ - Вверх\n↓ - Вниз\nОк - Выбрать\nУдержание Ок - Домой\nУдержание ↓ - Назад',
          ),
          const SizedBox(height: 12),
          _OutlinedButton(
            title: 'Начать работу',
            onTap: () {
              WearStatusIconReporter.I.send(WearGlassesPayload.menu());
              context.pop();
            },
          ),
        ],
      ),
    );
  }
}

class _OutlinedButton extends StatelessWidget {
  const _OutlinedButton({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: const BorderSide(color: WearColors.buttonPrimary, width: 2),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 48,
          child: Center(
            child: Text(
              title,
              style: const TextStyle(
                color: WearColors.buttonPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: WearTypography.lable,
        ),
        Text(
          body,
          style: WearTypography.bodysml,
        ),
      ],
    );
  }
}
