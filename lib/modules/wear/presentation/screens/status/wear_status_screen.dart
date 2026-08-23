import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/infrastructure/screen_lifecycle_logging.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_phone_feature_projection.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_scan_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearStatusScreen extends StatefulWidget {
  const WearStatusScreen({
    super.key,
    required this.args,
  });

  static const String route = '/wear_status_screen';

  /// Compatibility input for non-scan status flows. Migrated scan status always
  /// renders from the aggregate scan slice and cannot be overridden by route
  /// extras.
  final WearStatusScreenArgs? args;

  @override
  State<WearStatusScreen> createState() => _WearStatusScreenState();
}

class _WearStatusScreenState extends State<WearStatusScreen>
    with ScreenLifecycleLogging<WearStatusScreen> {
  @override
  Widget build(BuildContext context) {
    final authority = WearDependencies.I.authority;
    return StreamBuilder<WearRuntimeState>(
      stream: authority.states,
      initialData: authority.state,
      builder: (BuildContext context, AsyncSnapshot<WearRuntimeState> snapshot) {
        final WearRuntimeState state = snapshot.data ?? authority.state;
        final WearScanPhoneProjection projection =
            WearScanPhoneProjection.fromState(state);
        final WearStatusScreenArgs? aggregateStatus =
            projection.logicalScreen == WearScreenId.status &&
                    projection.phase == WearScanTaskPhase.status
                ? projection.status
                : null;
        final WearStatusScreenArgs args = aggregateStatus ??
            widget.args ??
            const WearStatusScreenArgs(
              kind: WearStatusKind.error,
              title: 'Ошибка',
              message: 'Нет данных для экрана',
            );
        return _StatusContent(args: args);
      },
    );
  }
}

class _StatusContent extends StatelessWidget {
  const _StatusContent({required this.args});

  final WearStatusScreenArgs args;

  @override
  Widget build(BuildContext context) {
    final String message = _normalizeStatusMessage(args.message);
    final String? iconPath = _statusIconFor(args);

    return WearScreenScaffold(
      showHomeButton: args.showHome,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(4.5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (iconPath != null) ...<Widget>[
                SvgPicture.asset(
                  iconPath,
                  colorFilter: const ColorFilter.mode(
                    WearColors.green,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(height: 7),
              ],
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

  static String _normalizeStatusMessage(String raw) {
    final String lower = raw.toLowerCase();
    if (lower.contains('error writing data to the connection')) {
      return 'Ошибка соединения с БД. Повторите попытку.';
    }
    return raw;
  }

  static String? _statusIconFor(WearStatusScreenArgs args) {
    if (args.kind == WearStatusKind.error) return WearImages.error;
    final bool isScanPrintSuccess = args.kind == WearStatusKind.success &&
        args.title.toLowerCase().contains('ценник');
    return isScanPrintSuccess ? WearImages.good : null;
  }
}
