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
    List<WearAvailabilityProduct> products,
  ) {
    return WearGlassesPayload(
      screenType: WearGlassesScreenType.availability,
      phase: WearGlassesPhase.idle,
      title: 'Дубль ШК',
      subtitle: 'Выберите товар',
      items: products
          .map((WearAvailabilityProduct product) => product.name)
          .toList(growable: false),
      selectedIndex: 0,
      pageText: _pageText(products.length),
    );
  }

  static WearGlassesPayload groups(List<WearAvailabilityGroup> groups) {
    if (groups.isEmpty) {
      return const WearGlassesPayload(
        screenType: WearGlassesScreenType.availability,
        phase: WearGlassesPhase.idle,
        title: 'Доступность',
        statusText: 'Нет заданий доступности',
      );
    }

    return WearGlassesPayload(
      screenType: WearGlassesScreenType.availability,
      phase: WearGlassesPhase.idle,
      title: 'Товарная группа',
      items: groups
          .map((WearAvailabilityGroup group) =>
              '${group.name} · ${group.counter}')
          .toList(growable: false),
      selectedIndex: 0,
      pageText: _pageText(groups.length),
    );
  }

  static WearGlassesPayload products({
    required WearAvailabilityGroup group,
    required List<WearAvailabilityProduct> products,
  }) {
    if (products.isEmpty) {
      return WearGlassesPayload(
        screenType: WearGlassesScreenType.availability,
        phase: WearGlassesPhase.idle,
        title: group.name,
        statusText: 'В группе нет заданий',
      );
    }

    return WearGlassesPayload(
      screenType: WearGlassesScreenType.availability,
      phase: WearGlassesPhase.idle,
      title: 'Товарная позиция',
      subtitle: group.name,
      items: products
          .map(
            (WearAvailabilityProduct product) =>
                '${product.name} · ост. ${_rest(product.rest)}',
          )
          .toList(growable: false),
      selectedIndex: 0,
      pageText: _pageText(products.length),
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
          title: 'Проверка товарной позиции',
          bodyLines: productLines,
          checkLines: checkLines,
          statusText: 'Товар есть на полке?',
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
          title: 'Фотофиксация',
          bodyLines: productLines,
          checkLines: checkLines,
          statusText: flow.message ?? 'Сделайте фото выкладки',
          primaryAction: 'Фото сделано',
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
          title: 'Готово',
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

  static String? _pageText(int itemCount) {
    if (itemCount <= 4) return null;
    return 'Страница: 1 из ${((itemCount - 1) ~/ 4) + 1}';
  }
}
