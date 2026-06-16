import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_scaling_list_view.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/services/wear_status_icon_reporter.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearProductSelectArgs {
  const WearProductSelectArgs({
    required this.barcode,
    required this.products,
  });
  final String barcode;
  final List<BarcodeProductInfo> products;
}

class WearProductSelectScreen extends StatefulWidget {
  const WearProductSelectScreen({super.key, required this.args});

  static const String route = '/wear_product_select';

  final WearProductSelectArgs? args;

  @override
  State<WearProductSelectScreen> createState() =>
      _WearProductSelectScreenState();
}

class _WearProductSelectScreenState extends State<WearProductSelectScreen> {
  final ScrollController _scroll = ScrollController();
  int _focusedIndex = 0;

  @override
  void initState() {
    super.initState();
    WearDependencies.I.wearFlowController.enterScreen(
      WearScreenId.productSelect,
      extra: widget.args,
    );
    WearDependencies.I.wearFlowController.registerScreenActions(
      WearScreenId.productSelect,
      WearScreenActionHandler(
        onUp: _onVoiceUp,
        onDown: _onVoiceDown,
        onSelect: _onVoiceSelect,
      ),
    );
  }

  @override
  void dispose() {
    WearDependencies.I.wearFlowController.unregisterScreenActions(
      WearScreenId.productSelect,
    );
    _scroll.dispose();
    super.dispose();
  }

  void _sendGlassesFocus() {
    final List<BarcodeProductInfo> products =
        widget.args?.products ?? <BarcodeProductInfo>[];
    if (products.isEmpty) return;
    final int idx = _focusedIndex.clamp(0, products.length - 1);
    WearStatusIconReporter.I.sendFast(
      WearGlassesPayload(
        screenType: WearGlassesScreenType.productSelect,
        phase: WearGlassesPhase.idle,
        title: 'Дубль ШК',
        subtitle: 'Выберите нужный товар',
        items: products.map((BarcodeProductInfo p) => p.name).toList(),
        selectedIndex: idx,
        pageText: products.length > 4 ? 'Показаны первые 4' : null,
      ),
    );
  }

  void _onVoiceUp() {
    final List<BarcodeProductInfo> products =
        widget.args?.products ?? <BarcodeProductInfo>[];
    if (products.isEmpty) return;
    _focusedIndex = _focusedIndex.clamp(0, products.length - 1);
    if (_focusedIndex <= 0) return;
    _focusedIndex = _focusedIndex - 1;
    final double target = ((_focusedIndex + 1) * 56.0).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(target,
        duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
    _sendGlassesFocus();
  }

  void _onVoiceDown() {
    final List<BarcodeProductInfo> products =
        widget.args?.products ?? <BarcodeProductInfo>[];
    if (products.isEmpty) return;
    _focusedIndex = _focusedIndex.clamp(0, products.length - 1);
    if (_focusedIndex >= products.length - 1) return;
    _focusedIndex = _focusedIndex + 1;
    final double target = ((_focusedIndex + 1) * 56.0).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(target,
        duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
    _sendGlassesFocus();
  }

  void _onVoiceSelect() {
    final List<BarcodeProductInfo> products =
        widget.args?.products ?? <BarcodeProductInfo>[];
    if (products.isEmpty) return;
    final int productIndex = _focusedIndex.clamp(0, products.length - 1);
    context.pop(products[productIndex]);
  }

  @override
  Widget build(BuildContext context) {
    final List<BarcodeProductInfo> products =
        widget.args?.products ?? <BarcodeProductInfo>[];
    if (products.isEmpty) {
      return WearScreenScaffold(
        showHomeButton: true,
        child: Center(
          child: Text(
            'Товары не найдены',
            style: WearTypography.lable,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return WearScreenScaffold(
      showHomeButton: true,
      scrollController: _scroll,
      child: WearScalingListView(
        controller: _scroll,
        itemCount: products.length + 2,
        itemExtent: 56,
        padding: const EdgeInsets.fromLTRB(0, 40, 0, 4.5),
        edgeFractionTop: 0.0,
        minScale: 0.68,
        minOpacity: 0.26,
        extraSideInset: 40,
        itemBuilder: (BuildContext context, int i) {
          if (i == 0) {
            final String barcode = widget.args?.barcode ?? '';
            final String header = barcode.trim().isEmpty
                ? 'Несколько товаров'
                : 'Несколько товаров\nс ШК $barcode';
            return Align(
              alignment: Alignment.topCenter,
              child: Text(
                header,
                style: WearTypography.lable,
                textAlign: TextAlign.center,
              ),
            );
          }

          if (i == products.length + 1) {
            return const SizedBox.shrink();
          }

          final BarcodeProductInfo product = products[i - 1];
          return WearPill(
            title: _resolveTitle(product),
            subtitle: _resolveSubtitle(product),
            onTap: () => context.pop(product),
            onLongPress: () => _showProductDialog(context, product),
          );
        },
        onFocusChanged: (int listIndex) {
          final List<BarcodeProductInfo> current =
              widget.args?.products ?? <BarcodeProductInfo>[];
          if (current.isEmpty) return;
          final int itemIndex = (listIndex - 1).clamp(0, current.length - 1);
          WearStatusIconReporter.I.sendFast(
            WearGlassesPayload(
              screenType: WearGlassesScreenType.productSelect,
              phase: WearGlassesPhase.idle,
              title: 'Дубль ШК',
              subtitle: 'Выберите нужный товар',
              items: current.map((BarcodeProductInfo p) => p.name).toList(),
              selectedIndex: itemIndex,
              pageText: current.length > 4 ? 'Показаны первые 4' : null,
            ),
          );
        },
      ),
    );
  }

  String _resolveTitle(BarcodeProductInfo product) {
    final String name = product.name;
    if (name.trim().isEmpty) {
      return 'Без названия';
    }
    return name;
  }

  String? _resolveSubtitle(BarcodeProductInfo product) {
    final List<String> parts = <String>[];
    if (product.weight != null) {
      parts.add('Вес: ${product.weight}');
    }
    if (product.articleRest != null) {
      parts.add('Остаток: ${product.articleRest}');
    }
    if (parts.isEmpty) {
      return null;
    }
    return parts.join(' · ');
  }

  Future<void> _showProductDialog(
    BuildContext context,
    BarcodeProductInfo product,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        final Size screen = MediaQuery.of(dialogContext).size;
        final double diameter =
            (screen.shortestSide - 12).clamp(160.0, screen.shortestSide);
        return Dialog(
          insetPadding: EdgeInsets.zero,
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Center(
            child: SizedBox.square(
              dimension: diameter,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: WearColors.buttonPrimary,
                    width: 0.4,
                  ),
                ),
                child: ClipOval(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                    child: Column(
                      children: <Widget>[
                        Align(
                          alignment: Alignment.topRight,
                          child: InkWell(
                            onTap: () => Navigator.of(dialogContext).pop(),
                            child: const Icon(
                              Icons.close,
                              color: WearColors.buttonPrimary,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  _buildTitle(product),
                                  style: WearTypography.lable15,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _buildDetails(product),
                                  style: WearTypography.bodysml,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: WearColors.buttonPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text('Закрыть'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _buildTitle(BarcodeProductInfo product) {
    final List<String> lines = <String>[
      _resolveTitle(product),
    ];
    return lines.join('\n');
  }

  String _buildDetails(BarcodeProductInfo product) {
    final String barcode = widget.args?.barcode ?? '';
    final List<String> lines = <String>[];
    if (barcode.trim().isNotEmpty) {
      lines.add('ШК: $barcode');
    }
    if (product.weight != null) {
      lines.add('Вес: ${product.weight}');
    }
    if (product.articleRest != null) {
      lines.add('Остаток: ${product.articleRest}');
    }
    return lines.join('\n');
  }
}
