import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_flow_state.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_group.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/domain/availability/use_case/wear_availability_flow_use_case.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';

class WearAvailabilityGlassesPayloads {
  const WearAvailabilityGlassesPayloads._();

  static WearGlassesPayload interactionTypes({int selectedIndex = 0}) {
    return WearGlassesPayload(
      screenType: WearGlassesScreenType.availability,
      phase: WearGlassesPhase.idle,
      title: 'Тип взаимодействия',
      items: const <String>['Список', 'Прямое сканирование'],
      selectedIndex: selectedIndex,
    );
  }

  static WearGlassesPayload directScanWaiting({
    String statusText = 'Поиск ШК...',
  }) {
    return WearGlassesPayload(
      screenType: WearGlassesScreenType.availability,
      phase: WearGlassesPhase.scanning,
      title: 'Сканирование товара',
      subtitle: 'Наведите камеру на штрих-код',
      statusText: statusText,
      statusIcon: WearImages.barcode,
    );
  }

  static WearGlassesPayload duplicates(
    List<WearAvailabilityProduct> products, {
    int selectedIndex = 0,
  }) {
    final int selected = selectedIndex.clamp(0, products.length - 1);
    final int start = _pageStart(selected);
    final List<WearAvailabilityProduct> visibleProducts = products
        .skip(start)
        .take(_visibleListItemCount)
        .toList(growable: false);

    return WearGlassesPayload(
      screenType: WearGlassesScreenType.availability,
      phase: WearGlassesPhase.idle,
      title: 'Дубль ШК',
      subtitle: 'Выберите товар',
      items: visibleProducts
          .map((WearAvailabilityProduct product) => product.name)
          .toList(growable: false),
      selectedIndex: selected - start,
      pageText: _pageText(products.length, selected),
    );
  }

  static WearGlassesPayload groups(
    List<WearAvailabilityGroup> groups, {
    int selectedIndex = 0,
  }) {
    if (groups.isEmpty) {
      return const WearGlassesPayload(
        screenType: WearGlassesScreenType.availability,
        phase: WearGlassesPhase.idle,
        title: 'Доступность',
        statusText: 'Нет заданий доступности',
      );
    }

    final int selected = selectedIndex.clamp(0, groups.length - 1);
    final int start = _pageStart(selected);
    final List<WearAvailabilityGroup> visibleGroups =
        groups.skip(start).take(_visibleListItemCount).toList(growable: false);

    return WearGlassesPayload(
      screenType: WearGlassesScreenType.availability,
      phase: WearGlassesPhase.idle,
      title: 'Товарная группа',
      items: visibleGroups
          .map((WearAvailabilityGroup group) =>
              '${group.name} · ${group.counter}')
          .toList(growable: false),
      selectedIndex: selected - start,
      pageText: _pageText(groups.length, selected),
    );
  }

  static WearGlassesPayload products({
    required WearAvailabilityGroup group,
    required List<WearAvailabilityProduct> products,
    int selectedIndex = 0,
  }) {
    if (products.isEmpty) {
      return WearGlassesPayload(
        screenType: WearGlassesScreenType.availability,
        phase: WearGlassesPhase.idle,
        title: group.name,
        statusText: 'В группе нет заданий',
      );
    }

    final int selected = selectedIndex.clamp(0, products.length - 1);
    final int start = _pageStart(selected);
    final List<WearAvailabilityProduct> visibleProducts = products
        .skip(start)
        .take(_visibleListItemCount)
        .toList(growable: false);

    return WearGlassesPayload(
      screenType: WearGlassesScreenType.availability,
      phase: WearGlassesPhase.idle,
      title: 'Товарная позиция',
      subtitle: group.name,
      items: visibleProducts
          .map(
            (WearAvailabilityProduct product) =>
                '${product.name} · ост. ${_rest(product.rest)}',
          )
          .toList(growable: false),
      selectedIndex: selected - start,
      pageText: _pageText(products.length, selected),
    );
  }

  static WearGlassesPayload loading({
    required String title,
    String? subtitle,
    String statusText = 'Загружаем...',
    String? statusIcon,
  }) {
    return WearGlassesPayload.loading(
      screenType: WearGlassesScreenType.availability,
      title: title,
      subtitle: subtitle,
      statusText: statusText,
      statusIcon: statusIcon,
    );
  }

  static WearGlassesPayload error({
    required String title,
    String? message,
  }) {
    return WearGlassesPayload.status(
      isError: true,
      title: title,
      subtitle: message,
      statusText: 'Ошибка',
    );
  }

  static WearGlassesPayload fromFlow(WearAvailabilityFlowState flow) {
    final WearAvailabilityProduct? product = flow.selectedProduct;
    final List<String> productLines =
        product == null ? const <String>[] : _productLines(product);
    final List<String> checkLines = _checkLines(flow);

    return switch (flow.step) {
      WearAvailabilityFlowStep.productQuestion => WearGlassesPayload(
          screenType: WearGlassesScreenType.availability,
          phase: WearGlassesPhase.idle,
          title: 'Товар есть на полке?',
          subtitle: product == null
              ? null
              : '${product.name}\nЦена: ${_price(product)}',
          primaryAction: 'Да',
          secondaryAction: 'Нет',
        ),
      WearAvailabilityFlowStep.productScan => WearGlassesPayload(
          screenType: WearGlassesScreenType.availability,
          phase: WearGlassesPhase.scanning,
          title: 'Проверка товарной позиции',
          bodyLines: productLines,
          checkLines: checkLines,
          statusText: flow.message ?? 'Поиск ШК...',
          statusIcon: WearImages.barcode,
        ),
      WearAvailabilityFlowStep.priceTagScan => WearGlassesPayload(
          screenType: WearGlassesScreenType.availability,
          phase: WearGlassesPhase.scanning,
          title: 'Проверка товарной позиции',
          bodyLines: productLines,
          checkLines: checkLines,
          statusText: flow.message ?? 'Поиск ШК ценника...',
          statusIcon: WearImages.barcode,
        ),
      WearAvailabilityFlowStep.priceTagOutdated => WearGlassesPayload(
          screenType: WearGlassesScreenType.availability,
          phase: WearGlassesPhase.idle,
          title: 'Ценник не актуален',
          bodyLines: productLines,
          checkLines: checkLines,
          statusText: flow.message ?? 'Напечатайте новый ценник',
          primaryAction: 'Напечатать',
          statusIcon: WearImages.printer,
        ),
      WearAvailabilityFlowStep.photoCapture => WearGlassesPayload(
          screenType: WearGlassesScreenType.availability,
          phase: WearGlassesPhase.idle,
          title: 'Фотоконтроль',
          bodyLines: productLines,
          checkLines: checkLines,
          statusText: flow.message ?? 'Сделайте фотографию товара',
          primaryAction: 'Сделать фото',
        ),
      WearAvailabilityFlowStep.readyToComplete => WearGlassesPayload(
          screenType: WearGlassesScreenType.availability,
          phase: WearGlassesPhase.idle,
          title: 'Завершение проверки',
          bodyLines: productLines,
          checkLines: checkLines,
          statusText: flow.message ?? 'Можно завершить проверку',
          primaryAction: 'Завершить',
          statusIcon: WearImages.ok,
        ),
      WearAvailabilityFlowStep.manualInventoryRequired => WearGlassesPayload(
          screenType: WearGlassesScreenType.availability,
          phase: WearGlassesPhase.error,
          title: 'Инвентаризация',
          bodyLines: productLines,
          checkLines: checkLines,
          statusText: WearAvailabilityFlowUseCase.manualInventoryMessage,
          primaryAction: 'Завершить',
          statusIcon: WearImages.error,
        ),
      WearAvailabilityFlowStep.completed => WearGlassesPayload(
          screenType: WearGlassesScreenType.availability,
          phase: WearGlassesPhase.success,
          title: 'Проверка завершена',
          bodyLines: productLines,
          checkLines: checkLines,
          statusText: flow.message ?? 'Проверка товара завершена',
          primaryAction: 'К списку',
          statusIcon: WearImages.good,
        ),
      _ => const WearGlassesPayload(
          screenType: WearGlassesScreenType.availability,
          phase: WearGlassesPhase.idle,
          title: 'Доступность',
        ),
    };
  }

  static List<String> _productLines(WearAvailabilityProduct product) {
    return <String>[
      product.name,
      'SKU код: ${product.code}',
      'Цена: ${_price(product)}',
      if (product.loyaltyPrice != null)
        'Цена по карте лояльности: ${_priceValue(product.loyaltyPrice!)}',
    ];
  }

  static List<String> _checkLines(WearAvailabilityFlowState flow) {
    final WearAvailabilityProductCheck? check = flow.check;
    if (check == null) return const <String>[];
    final WearAvailabilityProduct product = check.product;
    return <String>[
      if (!product.unpackaged)
        'ШК товара: ${check.productScanned ? 'ок' : 'ожидает'}',
      if (product.checkPrice) 'ШК ценника: ${_priceTagStatus(check)}',
      if (check.priceTagOutdated)
        'Печать: ${check.priceTagPrinted ? 'ок' : 'ожидает'}',
      if (product.photoControl)
        'Фото: ${check.photoCaptured ? 'ок' : 'ожидает'}',
    ];
  }

  static String _priceTagStatus(WearAvailabilityProductCheck check) {
    if (!check.priceTagScanned) return 'ожидает';
    if (check.priceTagOutdated) return 'неактуален';
    return 'ок';
  }

  static String _rest(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  static String _price(WearAvailabilityProduct product) {
    return _priceValue(product.price);
  }

  static String _priceValue(double value) {
    return '${value.toStringAsFixed(2).replaceAll('.', ',')} ₽';
  }

  static const int _visibleListItemCount = 4;

  static int _pageStart(int selectedIndex) {
    return (selectedIndex ~/ _visibleListItemCount) * _visibleListItemCount;
  }

  static String? _pageText(int itemCount, int selectedIndex) {
    if (itemCount <= _visibleListItemCount) return null;
    final int page = (selectedIndex ~/ _visibleListItemCount) + 1;
    final int pageCount = ((itemCount - 1) ~/ _visibleListItemCount) + 1;
    return 'Страница: $page из $pageCount';
  }
}
