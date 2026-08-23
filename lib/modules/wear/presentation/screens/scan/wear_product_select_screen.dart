import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';
import 'package:smart_glasses/modules/wear/infrastructure/screen_lifecycle_logging.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_scaling_list_view.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_phone_feature_projection.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_scan_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';
import 'package:smart_glasses/modules/wear/theme/wear_colors.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearProductSelectScreen extends StatefulWidget {
  const WearProductSelectScreen({super.key});

  static const String route = '/wear_product_select';

  @override
  State<WearProductSelectScreen> createState() =>
      _WearProductSelectScreenState();
}

class _WearProductSelectScreenState extends State<WearProductSelectScreen>
    with ScreenLifecycleLogging<WearProductSelectScreen> {
  final ScrollController _scroll = ScrollController();
  final WearRuntimeAuthority _authority = WearDependencies.I.authority;
  StreamSubscription<WearRuntimeState>? _runtimeSub;
  late WearScanPhoneProjection _projection;

  @override
  void initState() {
    super.initState();
    _projection = WearScanPhoneProjection.fromState(_authority.state);
    _runtimeSub = _authority.states.listen(_onRuntimeState);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToFocused(animate: false);
    });
  }

  @override
  void dispose() {
    unawaited(_runtimeSub?.cancel());
    _scroll.dispose();
    super.dispose();
  }

  void _onRuntimeState(WearRuntimeState state) {
    final WearScanPhoneProjection next =
        WearScanPhoneProjection.fromState(state);
    final int previousFocus = _projection.focusedIndex;
    if (mounted) {
      setState(() => _projection = next);
    } else {
      _projection = next;
    }
    if (next.logicalScreen == WearScreenId.productSelect &&
        previousFocus != next.focusedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToFocused();
      });
    }
  }

  void _requestFocus(int index) {
    if (_projection.logicalScreen != WearScreenId.productSelect ||
        _projection.phase != WearScanTaskPhase.selecting ||
        _projection.products.isEmpty) {
      return;
    }
    final int normalized = index.clamp(0, _projection.products.length - 1);
    unawaited(_authority.focusScanProduct(normalized));
  }

  Future<void> _selectProduct(BarcodeProductInfo candidate) async {
    final WearScanPhoneProjection current =
        WearScanPhoneProjection.fromState(_authority.state);
    if (current.logicalScreen != WearScreenId.productSelect ||
        current.phase != WearScanTaskPhase.selecting) {
      return;
    }
    final BarcodeProductInfo? product = current.productById(candidate.id);
    if (product == null) return;
    await _authority.selectScanProduct(product.id);
  }

  void _scrollToFocused({bool animate = true}) {
    if (!_scroll.hasClients || _projection.products.isEmpty) return;
    final double target = ((_projection.focusedIndex + 1) * 56.0).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    if (animate) {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    } else {
      _scroll.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<BarcodeProductInfo> products = _projection.products;
    if (_projection.logicalScreen != WearScreenId.productSelect ||
        _projection.phase != WearScanTaskPhase.selecting ||
        products.isEmpty) {
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
            final String barcode = _projection.barcode?.trim() ?? '';
            final String header = barcode.isEmpty
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
            onTap: () => _selectProduct(product),
            onLongPress: () => _showProductDialog(context, product),
          );
        },
        onFocusChanged: (int listIndex) {
          final int itemIndex = (listIndex - 1).clamp(0, products.length - 1);
          if (itemIndex == _projection.focusedIndex) return;
          _requestFocus(itemIndex);
        },
      ),
    );
  }

  String _resolveTitle(BarcodeProductInfo product) {
    final String name = product.name.trim();
    return name.isEmpty ? 'Без названия' : name;
  }

  String? _resolveSubtitle(BarcodeProductInfo product) {
    final List<String> parts = <String>[];
    if (product.weight != null) parts.add('Вес: ${product.weight}');
    if (product.articleRest != null) {
      parts.add('Остаток: ${product.articleRest}');
    }
    return parts.isEmpty ? null : parts.join(' · ');
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
        final String barcode = _projection.barcode?.trim() ?? '';
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
                                  _resolveTitle(product),
                                  style: WearTypography.lable15,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  <String>[
                                    if (barcode.isNotEmpty) 'ШК: $barcode',
                                    if (product.weight != null)
                                      'Вес: ${product.weight}',
                                    if (product.articleRest != null)
                                      'Остаток: ${product.articleRest}',
                                  ].join('\n'),
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
}
