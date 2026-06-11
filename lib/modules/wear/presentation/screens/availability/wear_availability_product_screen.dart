import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_group.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_availability_glasses_payloads.dart';
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

  @override
  void dispose() {
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
      ),
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
    List<WearAvailabilityProduct> products,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WearStatusIconReporter.I.send(
        WearAvailabilityGlassesPayloads.products(
          group: group,
          products: products,
        ),
      );
    });
  }

  void _sendLoading(WearAvailabilityGroup group) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WearStatusIconReporter.I.send(
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
      WearStatusIconReporter.I.send(
        WearAvailabilityGlassesPayloads.error(
          title: 'Ошибка доступности',
          message: _asUiMessage(error),
        ),
      );
    });
  }

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
