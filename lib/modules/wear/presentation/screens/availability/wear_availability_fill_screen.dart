import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:multi_scanner/multi_scanner.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/input/wear_print_code_input_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_loading.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/services/wear_status_icon_reporter.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearAvailabilityFillScreen extends StatefulWidget {
  const WearAvailabilityFillScreen({super.key});

  static const String route = '/wear_availability_fill';

  @override
  State<WearAvailabilityFillScreen> createState() =>
      _WearAvailabilityFillScreenState();
}

class _WearAvailabilityFillScreenState extends State<WearAvailabilityFillScreen>
    implements MultiScannerDelegate {
  final MultiScanner _scanner = MultiScanner.last();

  bool _isLoading = false;
  int _savedCount = 0;
  String _message = 'Сканируйте товары с полки';
  String? _lastBarcode;

  @override
  void initState() {
    super.initState();
    _scanner.addDelegate(this);
    WearDependencies.I.wearFlowController.enterScreen(
      WearScreenId.availabilityFill,
    );
    WearDependencies.I.wearFlowController.registerScreenActions(
      WearScreenId.availabilityFill,
      WearScreenActionHandler(
        onSelect: _manualInput,
        onDown: _reset,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendGlassesState();
    });
  }

  @override
  void dispose() {
    WearDependencies.I.wearFlowController.unregisterScreenActions(
      WearScreenId.availabilityFill,
    );
    _scanner.removeDelegate(this);
    super.dispose();
  }

  @override
  bool? onScanEvent(String payload) {
    _addBarcode(payload);
    return true;
  }

  @override
  bool? onErrorScan(Exception error) {
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return WearScreenScaffold(
      showHomeButton: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 28, 14, 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'Наполнение базы',
              style: WearTypography.lable18,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            if (_isLoading) const WearLoading(size: 44),
            if (_isLoading) const SizedBox(height: 12),
            Text(
              _message,
              style: WearTypography.bodysml,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Добавлено: $_savedCount',
              style: WearTypography.bodyxsm,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: 150,
                  child: WearPill(
                    title: 'Ручной ввод',
                    icon: WearImages.barcode,
                    onTap: _manualInput,
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: WearPill(
                    title: 'Очистить',
                    icon: WearImages.clear,
                    onTap: _reset,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _manualInput() async {
    final String? code = await context.push<String>(
      WearPrintCodeInputScreen.route,
    );
    if (code == null || code.trim().isEmpty) return;
    await _addBarcode(code);
  }

  Future<void> _addBarcode(String barcode) async {
    if (_isLoading) return;
    final String normalized = barcode.trim();
    if (normalized.isEmpty || normalized == _lastBarcode) return;
    setState(() {
      _isLoading = true;
      _lastBarcode = normalized;
      _message = 'Получаем товар...';
    });
    _sendGlassesState();

    try {
      final List<WearAvailabilityProduct> products = await WearDependencies.I
          .availabilityCatalogFillUseCase()
          .addByBarcode(normalized);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _savedCount += products.length;
        _message = products.length == 1
            ? 'Добавлено: ${products.first.name}'
            : 'Добавлено позиций: ${products.length}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _lastBarcode = null;
        _message = _asUiMessage(error);
      });
    }
    _sendGlassesState();
  }

  Future<void> _reset() async {
    if (_isLoading) return;
    await WearDependencies.I.availabilityCatalogFillUseCase().reset();
    if (!mounted) return;
    setState(() {
      _savedCount = 0;
      _lastBarcode = null;
      _message = 'База сканированной полки очищена';
    });
    _sendGlassesState();
  }

  void _sendGlassesState() {
    WearStatusIconReporter.I.send(
      WearGlassesPayload(
        screenType: WearGlassesScreenType.availability,
        phase: _isLoading ? WearGlassesPhase.loading : WearGlassesPhase.idle,
        title: 'Наполнение базы',
        statusText: _message,
        isLoading: _isLoading,
        statusIcon: _isLoading ? WearImages.barcode : WearImages.database,
        bodyLines: <String>['Добавлено: $_savedCount'],
      ),
    );
  }

  String _asUiMessage(Object error) {
    final String raw = error.toString();
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length);
    }
    return raw;
  }
}
