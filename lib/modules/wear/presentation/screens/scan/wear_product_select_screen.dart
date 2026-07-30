import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_list_matcher.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/domain/price_tag_print/model/barcode_product_info.dart';
import 'package:smart_glasses/modules/wear/infrastructure/screen_lifecycle_logging.dart';
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

class _WearProductSelectScreenState extends State<WearProductSelectScreen>
    with ScreenLifecycleLogging<WearProductSelectScreen> {
  final ScrollController _scroll = ScrollController();
  int _focusedIndex = 0;
  bool _isProductDialogOpen = false;

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
        onCancel: _onVoiceCancel,
        onNextPage: _onVoiceNextPage,
        onPreviousPage: _onVoicePreviousPage,
        onPhrase: _onVoicePhrase,
        dynamicVoiceItems: _dynamicVoiceItems,
        onPartialPhrase: _onVoicePartialPhrase,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sendGlassesFocus();
    });
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
    final int start = _pageStart(idx);
    final List<BarcodeProductInfo> visibleProducts = products
        .skip(start)
        .take(_visibleGlassesItemCount)
        .toList(growable: false);
    final WearGlassesPayload payload = WearGlassesPayload(
      screenType: WearGlassesScreenType.productSelect,
      phase: WearGlassesPhase.idle,
      title: 'Дубль ШК',
      subtitle: 'Выберите нужный товар',
      items: visibleProducts
          .map((BarcodeProductInfo p) => p.name)
          .toList(growable: false),
      selectedIndex: idx - start,
      pageText: _pageText(products.length, idx),
    );
    WearDependencies.I.wearFlowController.rememberScreenPayload(
      WearScreenId.productSelect,
      payload,
    );
    WearStatusIconReporter.I.sendFastForScreen(
      WearScreenId.productSelect,
      payload,
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

  void _onVoiceNextPage() {
    final List<BarcodeProductInfo> products =
        widget.args?.products ?? <BarcodeProductInfo>[];
    if (products.isEmpty) return;
    final int currentPage = _focusedIndex ~/ _visibleGlassesItemCount;
    final int nextIndex = (currentPage + 1) * _visibleGlassesItemCount;
    if (nextIndex >= products.length) {
      _showVoiceSearchMessage('Это последняя страница');
      return;
    }
    _focusedIndex = nextIndex.clamp(0, products.length - 1);
    _scrollToFocused();
    _sendGlassesFocus();
  }

  void _onVoicePreviousPage() {
    final List<BarcodeProductInfo> products =
        widget.args?.products ?? <BarcodeProductInfo>[];
    if (products.isEmpty) return;
    final int currentPage = _focusedIndex ~/ _visibleGlassesItemCount;
    if (currentPage == 0) {
      _showVoiceSearchMessage('Это первая страница');
      return;
    }
    final int previousIndex = (currentPage - 1) * _visibleGlassesItemCount;
    _focusedIndex = previousIndex.clamp(0, products.length - 1);
    _scrollToFocused();
    _sendGlassesFocus();
  }

  VoiceDynamicItemsSnapshot _dynamicVoiceItems() {
    final List<BarcodeProductInfo> products =
        widget.args?.products ?? <BarcodeProductInfo>[];
    final List<VoiceDynamicItem> items = products
        .map((BarcodeProductInfo item) => VoiceDynamicItem(
              id: item.id.toString(),
              label: item.name,
            ))
        .toList(growable: false);
    return VoiceDynamicItemsSnapshot(
      revision: Object.hashAll(
        items.map((VoiceDynamicItem item) => Object.hash(item.id, item.label)),
      ),
      items: items,
    );
  }

  void _onVoicePhrase(String phrase) {
    final List<BarcodeProductInfo> products =
        widget.args?.products ?? <BarcodeProductInfo>[];
    if (products.isEmpty) return;
    final VoiceListMatch<BarcodeProductInfo> match = VoiceListMatcher.match(
      phrase,
      products,
      (BarcodeProductInfo product) => product.name,
    );
    switch (match.type) {
      case VoiceListMatchType.none:
        _showVoiceSearchMessage('Не найдено');
        break;
      case VoiceListMatchType.ambiguous:
        _showVoiceSearchMessage('Назовите точнее');
        break;
      case VoiceListMatchType.unique:
        final BarcodeProductInfo product = match.item!;
        final int index = products.indexOf(product);
        if (index >= 0) {
          _focusedIndex = index;
          _scrollToFocused();
          _sendGlassesFocus();
        }
        context.pop(product);
        break;
    }
  }

  bool _onVoicePartialPhrase(String phrase) {
    if (!VoiceListMatcher.canMatchPartial(phrase)) return false;
    final List<BarcodeProductInfo> products =
        widget.args?.products ?? <BarcodeProductInfo>[];
    if (products.isEmpty) return false;
    final VoiceListMatch<BarcodeProductInfo> match = VoiceListMatcher.match(
      phrase,
      products,
      (BarcodeProductInfo product) => product.name,
    );
    if (match.type != VoiceListMatchType.unique) {
      return false;
    }

    final BarcodeProductInfo product = match.item!;
    final int index = products.indexOf(product);
    if (index >= 0) {
      _focusedIndex = index;
      _scrollToFocused();
      _sendGlassesFocus();
    }
    return false;
  }

  void _onVoiceCancel() {
    if (!_isProductDialogOpen) return;
    Navigator.of(context, rootNavigator: true).pop();
  }

  void _scrollToFocused() {
    if (!_scroll.hasClients) return;
    final double target = ((_focusedIndex + 1) * 56.0).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  void _showVoiceSearchMessage(String message) {
    WearStatusIconReporter.I.showTransientFastForScreen(
      WearScreenId.productSelect,
      WearGlassesPayload.status(
        isError: true,
        title: 'Голосовой выбор',
        statusText: message,
      ),
    );
  }

  static const int _visibleGlassesItemCount = 4;

  int _pageStart(int selectedIndex) {
    return (selectedIndex ~/ _visibleGlassesItemCount) *
        _visibleGlassesItemCount;
  }

  String? _pageText(int itemCount, int selectedIndex) {
    if (itemCount <= _visibleGlassesItemCount) return null;
    final int page = (selectedIndex ~/ _visibleGlassesItemCount) + 1;
    final int pageCount = ((itemCount - 1) ~/ _visibleGlassesItemCount) + 1;
    return 'Страница: $page из $pageCount';
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
          _focusedIndex = itemIndex;
          _sendGlassesFocus();
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
    _isProductDialogOpen = true;
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
    _isProductDialogOpen = false;
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
