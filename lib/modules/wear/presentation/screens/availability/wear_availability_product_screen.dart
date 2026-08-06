import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/config/wear_dependencies.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_group.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_list_matcher.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_availability_glasses_payloads.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/cubit/wear_availability_list_providers.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/availability/wear_availability_check_screen.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_loading.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_pill.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_scaling_list_view.dart';
import 'package:smart_glasses/modules/wear/presentation/widgets/wear_screen_scaffold.dart';
import 'package:smart_glasses/modules/wear/services/wear_status_icon_reporter.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';
import 'package:smart_glasses/modules/wear/theme/wear_typography.dart';

class WearAvailabilityProductScreen extends ConsumerStatefulWidget {
  const WearAvailabilityProductScreen({
    super.key,
    required this.group,
  });

  static const String route = '/wear_availability_products';

  final WearAvailabilityGroup? group;

  @override
  ConsumerState<WearAvailabilityProductScreen> createState() =>
      _WearAvailabilityProductScreenState();
}

class _WearAvailabilityProductScreenState
    extends ConsumerState<WearAvailabilityProductScreen> {
  final ScrollController _scroll = ScrollController();
  int _focusedIndex = 0;
  List<WearAvailabilityProduct>? _voiceSnapshotProducts;
  VoiceDynamicItemsSnapshot _voiceSnapshot = VoiceDynamicItemsSnapshot.empty;

  @override
  void initState() {
    super.initState();
    WearDependencies.I.wearFlowController.enterScreen(
      WearScreenId.availabilityProduct,
      extra: widget.group,
    );
    WearDependencies.I.wearFlowController.registerScreenActions(
      WearScreenId.availabilityProduct,
      WearScreenActionHandler(
        onUp: _onVoiceUp,
        onDown: _onVoiceDown,
        onSelect: _onVoiceSelect,
        onNextPage: _onVoiceNextPage,
        onPreviousPage: _onVoicePreviousPage,
        onPhrase: _onVoicePhrase,
        onDynamicItem: _onVoiceDynamicItem,
        dynamicVoiceItems: _dynamicVoiceItems,
        onPartialPhrase: _onVoicePartialPhrase,
      ),
    );
  }

  @override
  void dispose() {
    WearDependencies.I.wearFlowController.unregisterScreenActions(
      WearScreenId.availabilityProduct,
    );
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final WearAvailabilityGroup? group = widget.group;
    if (group == null) {
      return WearScreenScaffold(
        showHomeButton: true,
        child: _buildMessage('Группа не выбрана'),
      );
    }

    final AsyncValue<List<WearAvailabilityProduct>> products =
        ref.watch(wearAvailabilityProductsProvider(group));
    products.whenData((List<WearAvailabilityProduct> value) {
      _sendGlassesState(group, value);
    });

    return WearScreenScaffold(
      showHomeButton: true,
      scrollController: _scroll,
      child: products.when(
        data: (List<WearAvailabilityProduct> value) =>
            _buildProducts(group, value),
        loading: () {
          _sendLoading(group);
          return const Center(child: WearLoading());
        },
        error: (Object error, StackTrace _) {
          _sendError(error);
          return _buildMessage('Ошибка загрузки\n${_asUiMessage(error)}');
        },
      ),
    );
  }

  Widget _buildProducts(
    WearAvailabilityGroup group,
    List<WearAvailabilityProduct> products,
  ) {
    if (products.isEmpty) {
      return _buildMessage('В группе нет заданий');
    }

    final int savedIndex = WearDependencies
        .I.wearFlowController.state.availabilityProductFocusedIndex
        .clamp(0, products.length - 1);
    if (_focusedIndex != savedIndex) {
      _focusedIndex = savedIndex;
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.refresh(wearAvailabilityProductsProvider(group).future),
      child: WearScalingListView(
        controller: _scroll,
        itemCount: products.length + 2,
        itemExtent: 56,
        padding: const EdgeInsets.fromLTRB(0, 40, 0, 4.5),
        edgeFractionTop: 0.0,
        minScale: 0.68,
        minOpacity: 0.26,
        extraSideInset: 40,
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        itemBuilder: (BuildContext context, int i) {
          if (i == 0) {
            return Align(
              alignment: Alignment.topCenter,
              child: Text(
                group.name,
                style: WearTypography.lable,
                textAlign: TextAlign.center,
              ),
            );
          }
          if (i == products.length + 1) {
            return const SizedBox.shrink();
          }

          final WearAvailabilityProduct product = products[i - 1];
          return WearPill(
            title: product.name,
            subtitle: 'Код ${product.code} · ост. ${_rest(product.rest)}',
            icon: WearImages.barcode,
            onTap: () => context.push(
              WearAvailabilityCheckScreen.route,
              extra: product,
            ),
          );
        },
        onFocusChanged: (int listIndex) {
          final int itemIndex = (listIndex - 1).clamp(0, products.length - 1);
          if (itemIndex == _focusedIndex) return;
          _focusedIndex = itemIndex;
          WearDependencies.I.wearFlowController
              .setAvailabilityProductFocusedIndex(
                  _focusedIndex, products.length);
          _sendGlassesState(group, products, fast: true);
        },
      ),
    );
  }

  void _onVoiceUp() {
    final WearAvailabilityGroup? group = widget.group;
    if (group == null) return;
    final List<WearAvailabilityProduct>? products =
        ref.read(wearAvailabilityProductsProvider(group)).valueOrNull;
    if (products == null || products.isEmpty) return;
    _focusedIndex = _focusedIndex.clamp(0, products.length - 1);
    if (_focusedIndex <= 0) return;
    _focusedIndex--;
    WearDependencies.I.wearFlowController
        .setAvailabilityProductFocusedIndex(_focusedIndex, products.length);
    _scrollToFocused();
    _sendGlassesState(group, products, fast: true);
  }

  void _onVoiceDown() {
    final WearAvailabilityGroup? group = widget.group;
    if (group == null) return;
    final List<WearAvailabilityProduct>? products =
        ref.read(wearAvailabilityProductsProvider(group)).valueOrNull;
    if (products == null || products.isEmpty) return;
    _focusedIndex = _focusedIndex.clamp(0, products.length - 1);
    if (_focusedIndex >= products.length - 1) return;
    _focusedIndex++;
    WearDependencies.I.wearFlowController
        .setAvailabilityProductFocusedIndex(_focusedIndex, products.length);
    _scrollToFocused();
    _sendGlassesState(group, products, fast: true);
  }

  void _onVoiceSelect() {
    final WearAvailabilityGroup? group = widget.group;
    if (group == null) return;
    final List<WearAvailabilityProduct>? products =
        ref.read(wearAvailabilityProductsProvider(group)).valueOrNull;
    if (products == null || products.isEmpty) return;
    final int productIndex = _focusedIndex.clamp(0, products.length - 1);
    context.push(WearAvailabilityCheckScreen.route,
        extra: products[productIndex]);
  }

  void _onVoiceNextPage() {
    final WearAvailabilityGroup? group = widget.group;
    if (group == null) return;
    final List<WearAvailabilityProduct>? products =
        ref.read(wearAvailabilityProductsProvider(group)).valueOrNull;
    if (products == null || products.isEmpty) return;
    final int currentPage = _focusedIndex ~/ _visibleGlassesItemCount;
    final int nextIndex = (currentPage + 1) * _visibleGlassesItemCount;
    if (nextIndex >= products.length) {
      _showVoiceSearchMessage('Это последняя страница');
      return;
    }
    _focusedIndex = nextIndex.clamp(0, products.length - 1);
    WearDependencies.I.wearFlowController
        .setAvailabilityProductFocusedIndex(_focusedIndex, products.length);
    _scrollToFocused();
    _sendGlassesState(group, products, fast: true);
  }

  void _onVoicePreviousPage() {
    final WearAvailabilityGroup? group = widget.group;
    if (group == null) return;
    final List<WearAvailabilityProduct>? products =
        ref.read(wearAvailabilityProductsProvider(group)).valueOrNull;
    if (products == null || products.isEmpty) return;
    final int currentPage = _focusedIndex ~/ _visibleGlassesItemCount;
    if (currentPage == 0) {
      _showVoiceSearchMessage('Это первая страница');
      return;
    }
    final int previousIndex = (currentPage - 1) * _visibleGlassesItemCount;
    _focusedIndex = previousIndex.clamp(0, products.length - 1);
    WearDependencies.I.wearFlowController
        .setAvailabilityProductFocusedIndex(_focusedIndex, products.length);
    _scrollToFocused();
    _sendGlassesState(group, products, fast: true);
  }

  VoiceDynamicItemsSnapshot _dynamicVoiceItems() {
    final WearAvailabilityGroup? group = widget.group;
    final List<WearAvailabilityProduct> products = group == null
        ? <WearAvailabilityProduct>[]
        : ref.read(wearAvailabilityProductsProvider(group)).valueOrNull ??
            <WearAvailabilityProduct>[];
    if (identical(products, _voiceSnapshotProducts)) return _voiceSnapshot;
    final Stopwatch stopwatch = Stopwatch()..start();
    final List<VoiceDynamicItem> items = products
        .map((WearAvailabilityProduct item) => VoiceDynamicItem(
              id: item.id.toString(),
              label: item.name,
            ))
        .toList(growable: false);
    _voiceSnapshotProducts = products;
    _voiceSnapshot = VoiceDynamicItemsSnapshot(
      revision: Object.hashAll(
        items.map((VoiceDynamicItem item) => item.revisionHash),
      ),
      items: items,
    );
    stopwatch.stop();
    print(
      '[VOICE_DYNAMIC_PERF] phase=snapshot screen=availabilityProduct '
      'items=${items.length} durationMs=${stopwatch.elapsedMilliseconds}',
    );
    return _voiceSnapshot;
  }

  void _onVoicePhrase(String phrase) {
    final WearAvailabilityGroup? group = widget.group;
    if (group == null) return;
    final List<WearAvailabilityProduct>? products =
        ref.read(wearAvailabilityProductsProvider(group)).valueOrNull;
    if (products == null || products.isEmpty) return;
    final VoiceListMatch<WearAvailabilityProduct> match =
        VoiceListMatcher.match(
      phrase,
      products,
      (WearAvailabilityProduct product) => product.name,
    );
    switch (match.type) {
      case VoiceListMatchType.none:
        WearStatusIconReporter.I.showTransientStatusText(
          WearScreenId.availabilityProduct, 'Ничего не найдено');
        break;
      case VoiceListMatchType.ambiguous:
        WearStatusIconReporter.I.showTransientStatusText(
          WearScreenId.availabilityProduct, 'Назовите точнее');
        break;
      case VoiceListMatchType.unique:
        _selectProduct(group, products, match.item!);
        break;
    }
  }

  void _onVoiceDynamicItem(String itemId) {
    final WearAvailabilityGroup? group = widget.group;
    if (group == null) return;
    final List<WearAvailabilityProduct>? products =
        ref.read(wearAvailabilityProductsProvider(group)).valueOrNull;
    if (products == null) return;
    for (final WearAvailabilityProduct product in products) {
      if (product.id.toString() == itemId) {
        _selectProduct(group, products, product);
        return;
      }
    }
  }

  void _selectProduct(
    WearAvailabilityGroup group,
    List<WearAvailabilityProduct> products,
    WearAvailabilityProduct product,
  ) {
    final int index = products.indexWhere((WearAvailabilityProduct item) {
      return item.id == product.id;
    });
    if (index >= 0) {
      _focusedIndex = index;
      WearDependencies.I.wearFlowController
          .setAvailabilityProductFocusedIndex(_focusedIndex, products.length);
      _scrollToFocused();
      _sendGlassesState(group, products, fast: true);
    }
    context.push(WearAvailabilityCheckScreen.route, extra: product);
  }

  bool _onVoicePartialPhrase(String phrase) {
    final WearAvailabilityGroup? group = widget.group;
    if (group == null) return false;
    final List<WearAvailabilityProduct>? products =
        ref.read(wearAvailabilityProductsProvider(group)).valueOrNull;
    if (products == null || products.isEmpty) return false;
    final VoiceListMatch<WearAvailabilityProduct> match =
        VoiceListMatcher.canMatchPartial(phrase)
            ? VoiceListMatcher.match(
                phrase,
                products,
                (WearAvailabilityProduct product) => product.name,
              )
            : VoiceListMatcher.matchExactPhrase(
                phrase,
                products,
                (WearAvailabilityProduct product) => product.name,
              );
    if (match.type != VoiceListMatchType.unique) {
      return false;
    }

    final WearAvailabilityProduct product = match.item!;
    final int index = products.indexWhere((WearAvailabilityProduct item) {
      return item.id == product.id;
    });
    if (index >= 0) {
      _focusedIndex = index;
      WearDependencies.I.wearFlowController
          .setAvailabilityProductFocusedIndex(_focusedIndex, products.length);
      _scrollToFocused();
      _sendGlassesState(group, products, fast: true);
    }
    return index >= 0;
  }

  void _scrollToFocused() {
    if (!_scroll.hasClients) return;
    const double itemExtent = 56.0;
    const double topPadding = 40.0;
    final double viewport = _scroll.position.viewportDimension;
    final int listIndex = _focusedIndex + 1;
    final double target =
        (topPadding + listIndex * itemExtent + itemExtent / 2 - viewport / 2)
            .clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  Widget _buildMessage(String message) {
    return Center(
      child: Text(
        message,
        style: WearTypography.lable,
        textAlign: TextAlign.center,
      ),
    );
  }

  void _sendGlassesState(
    WearAvailabilityGroup group,
    List<WearAvailabilityProduct> products, {
    bool fast = false,
  }) {
    if (fast) {
      _sendGlassesPayload(group, products, fast: true);
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendGlassesPayload(group, products);
    });
  }

  void _sendGlassesPayload(
    WearAvailabilityGroup group,
    List<WearAvailabilityProduct> products, {
    bool fast = false,
  }) {
    if (!mounted ||
        WearDependencies.I.wearFlowController.state.screen !=
            WearScreenId.availabilityProduct) {
      return;
    }
    final Stopwatch stopwatch = Stopwatch()..start();
    final VoiceDynamicItemsSnapshot voiceSnapshot = _dynamicVoiceItems();
    final payload = WearAvailabilityGlassesPayloads.products(
      group: group,
      products: products,
      voiceSnapshot: voiceSnapshot,
      selectedIndex: _focusedIndex,
      onVoiceHintsPrepared: () {
        if (!mounted) return;
        final List<WearAvailabilityProduct>? currentProducts =
            ref.read(wearAvailabilityProductsProvider(group)).valueOrNull;
        if (currentProducts == null ||
            _dynamicVoiceItems().revision != voiceSnapshot.revision) {
          return;
        }
        _sendGlassesPayload(group, currentProducts, fast: true);
      },
    );
    stopwatch.stop();
    if (products.length >= 100 || stopwatch.elapsedMilliseconds >= 20) {
      print(
        '[VOICE_DYNAMIC_PERF] phase=glasses_payload '
        'screen=availabilityProduct items=${products.length} '
        'durationMs=${stopwatch.elapsedMilliseconds} fast=$fast',
      );
    }
    WearDependencies.I.wearFlowController.rememberScreenPayload(
      WearScreenId.availabilityProduct,
      payload,
    );
    if (fast) {
      WearStatusIconReporter.I.sendFastForScreen(
        WearScreenId.availabilityProduct,
        payload,
      );
      return;
    }
    WearStatusIconReporter.I.sendForScreen(
      WearScreenId.availabilityProduct,
      payload,
    );
  }

  void _sendLoading(WearAvailabilityGroup group) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WearStatusIconReporter.I.sendForScreen(
        WearScreenId.availabilityProduct,
        WearAvailabilityGlassesPayloads.loading(
          title: group.name,
          statusText: 'Загружаем...',
          statusIcon: WearImages.database,
        ),
      );
    });
  }

  void _sendError(Object error) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WearStatusIconReporter.I.sendForScreen(
        WearScreenId.availabilityProduct,
        WearAvailabilityGlassesPayloads.error(
          title: 'Ошибка доступности',
          message: _asUiMessage(error),
        ),
      );
    });
  }

  void _showVoiceSearchMessage(String message) {
    WearStatusIconReporter.I.showTransientFastForScreen(
      WearScreenId.availabilityProduct,
      WearGlassesPayload.status(
        isError: true,
        title: 'Голосовой выбор',
        statusText: message,
      ),
    );
  }

  static const int _visibleGlassesItemCount = 4;

  String _rest(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  String _asUiMessage(Object error) {
    final String raw = error.toString();
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length);
    }
    return raw;
  }
}
