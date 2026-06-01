import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_bridge.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';
import 'package:flutter_svg/flutter_svg.dart';

class WearStatusScreen extends StatefulWidget {
  const WearStatusScreen({
    super.key,
    required this.args,
  });

  static const String route = '/wear_status_screen';

  final WearStatusScreenArgs? args;

  @override
  State<WearStatusScreen> createState() => _WearStatusScreenState();
}

class _WearStatusScreenState extends State<WearStatusScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    final WearStatusScreenArgs? a = widget.args;
    if (a == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      wearGlassesBridge.update(
        WearGlassesPayload.status(
          isError: a.kind == WearStatusKind.error,
          title: a.title,
          subtitle: a.message,
          statusText: a.kind == WearStatusKind.error ? 'Ошибка' : 'Успешно',
        ),
      );
    });

    final Duration? after = a.autoAfter;
    if (after == null) return;

    final WearStatusAutoAction action =
        a.autoAction == WearStatusAutoAction.none
            ? (a.autoRoute != null
                ? WearStatusAutoAction.go
                : WearStatusAutoAction.none)
            : a.autoAction;

    if (action == WearStatusAutoAction.none) return;

    _timer = Timer(after, () {
      if (!mounted) return;

      if (action == WearStatusAutoAction.pop) {
        context.pop();
        return;
      }

      if (action == WearStatusAutoAction.go) {
        final String? r = a.autoRoute;
        if (r == null) return;
        context.go(r, extra: a.autoExtra);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final WearStatusScreenArgs args = widget.args ??
        const WearStatusScreenArgs(
          kind: WearStatusKind.error,
          title: 'Ошибка',
          message: 'Нет данных для экрана',
        );
    final String message = _normalizeStatusMessage(args.message);

    final String iconPath = args.kind == WearStatusKind.success
        ? WearImages.good
        : WearImages.error;

    return WearScreenScaffold(
      showHomeButton: args.showHome,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(4.5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SvgPicture.asset(iconPath),
              const SizedBox(height: 7),
              Text(
                args.title,
                style: WearTypography.bodyxsm,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                message,
                style: WearTypography.bodysml,
                textAlign: TextAlign.center,
              ),
              if (args.details != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  args.details!,
                  style: WearTypography.bodyxsm
                      .copyWith(color: WearColors.textDefault),
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _normalizeStatusMessage(String raw) {
    final String lower = raw.toLowerCase();
    if (lower.contains('error writing data to the connection')) {
      return 'Ошибка соединения с БД. Повторите попытку.';
    }
    return raw;
  }
}
