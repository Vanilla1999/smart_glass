import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_group.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_availability_glasses_payloads.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_availability_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_control_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_scan_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';
import 'package:smart_glasses/modules/wear/theme/wear_images.dart';

class WearPhoneProjection {
  const WearPhoneProjection({
    required this.version,
    required this.logicalScreen,
    required this.focusedIndex,
    required this.items,
    required this.statusText,
  });

  final WearRuntimeVersion version;
  final WearScreenId logicalScreen;
  final int focusedIndex;
  final List<String> items;
  final String? statusText;
}

class WearGlassesEnvelope {
  const WearGlassesEnvelope({
    required this.sessionEpoch,
    required this.stateRevision,
    required this.logicalScreen,
    required this.payload,
    required this.overlay,
  });

  static const int schemaVersion = 1;
  final int sessionEpoch;
  final int stateRevision;
  final WearScreenId logicalScreen;
  final WearGlassesPayload payload;
  final WearProjectionOverlay overlay;

  WearRuntimeVersion get version => WearRuntimeVersion(
        sessionEpoch: sessionEpoch,
        revision: stateRevision,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': schemaVersion,
        'sessionEpoch': sessionEpoch,
        'stateRevision': stateRevision,
        'logicalScreen': logicalScreen.name,
        'payload': payload.toJson(),
        'overlay': <String, dynamic>{
          ...overlay.toJson(),
          'sessionEpoch': sessionEpoch,
          'stateRevision': stateRevision,
        },
      };
}

class WearProjectionOverlay {
  const WearProjectionOverlay({
    required this.visible,
    required this.phase,
    required this.message,
  });

  final bool visible;
  final String phase;
  final String? message;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'visible': visible,
        'phase': phase,
        'message': message,
      };
}

class WearRuntimeProjection {
  const WearRuntimeProjection._();

  static WearPhoneProjection projectPhone(WearRuntimeState state) {
    final WearGlassesPayload payload = _payload(state);
    return WearPhoneProjection(
      version: state.version,
      logicalScreen: _aggregate(state).navigation.logicalScreen,
      focusedIndex: payload.selectedIndex,
      items: List<String>.unmodifiable(payload.items),
      statusText: payload.statusText,
    );
  }

  static WearGlassesEnvelope projectGlasses(WearRuntimeState state) {
    final WearRuntimeControlPayload controls =
        _aggregate(state).controls as WearRuntimeControlPayload;
    return WearGlassesEnvelope(
      sessionEpoch: state.sessionEpoch,
      stateRevision: state.revision,
      logicalScreen: _aggregate(state).navigation.logicalScreen,
      payload: _payload(state),
      overlay: _overlay(controls.voice),
    );
  }

  static WearProjectionOverlay _overlay(WearVoiceControlSlice voice) {
    final bool visible = voice.phase != WearVoiceRuntimePhase.ready &&
        voice.phase != WearVoiceRuntimePhase.disabled;
    return WearProjectionOverlay(
      visible: visible,
      phase: voice.phase.name,
      message: switch (voice.phase) {
        WearVoiceRuntimePhase.starting =>
          'Подготовка\nголосового управления',
        WearVoiceRuntimePhase.reconnecting =>
          'Переподключаем\nголосовое управление',
        WearVoiceRuntimePhase.unavailable =>
          'Голосовое управление недоступно',
        WearVoiceRuntimePhase.disabled || WearVoiceRuntimePhase.ready => null,
      },
    );
  }

  static WearAggregatePayload _aggregate(WearRuntimeState state) =>
      state.payloadAs<WearAggregatePayload>();

  static WearGlassesPayload _payload(WearRuntimeState state) {
    final WearAggregatePayload aggregate = _aggregate(state);
    final WearScreenId screen = aggregate.navigation.logicalScreen;
    final WearRuntimeFeaturePayload features =
        aggregate.features as WearRuntimeFeaturePayload;
    final WearRuntimeControlPayload controls =
        aggregate.controls as WearRuntimeControlPayload;
    final WearPresentationFocusSlice presentation =
        aggregate.presentation as WearPresentationFocusSlice;
    final WearGlassesPayload base = switch (screen) {
      WearScreenId.menu => WearGlassesPayload.menu(
          selectedIndex: presentation.focusFor(screen),
        ),
      WearScreenId.homeConfirm => WearGlassesPayload.homeConfirm(
          selectedIndex: presentation.focusFor(screen),
        ),
      WearScreenId.help => WearGlassesPayload.help(),
      WearScreenId.continueScan => WearGlassesPayload.continueScan(
          selectedIndex: presentation.focusFor(screen),
        ),
      WearScreenId.printerSelect => _printer(features.printer),
      WearScreenId.scanIdle ||
      WearScreenId.productSelect ||
      WearScreenId.status =>
        _scan(features.scan as WearScanTaskSlice),
      WearScreenId.availabilityInteraction =>
        WearAvailabilityGlassesPayloads.interactionTypes(
          selectedIndex: presentation.focusFor(screen),
        ),
      WearScreenId.availabilityGroup ||
      WearScreenId.availabilityProduct ||
      WearScreenId.availabilityDirectScan ||
      WearScreenId.availabilityCheck ||
      WearScreenId.availabilityFill =>
        _availability(features.availability as WearAvailabilityTaskSlice),
      WearScreenId.scannerConnect => WearGlassesPayload.loading(
          screenType: WearGlassesScreenType.status,
          title: 'Сканер',
          statusText: 'Подключение...',
        ),
      WearScreenId.main => WearGlassesPayload.authWaitingBarcode(),
      WearScreenId.voiceClarification => WearGlassesPayload.status(
          isError: false,
          title: 'Уточните команду',
        ),
      WearScreenId.printCodeInput => WearGlassesPayload.loading(
          screenType: WearGlassesScreenType.printing,
          title: 'Ввод кода',
          statusText: 'Введите код на телефоне',
        ),
      WearScreenId.settings ||
      WearScreenId.dbSettings ||
      WearScreenId.wifiSettings ||
      WearScreenId.printerSettings =>
        WearGlassesPayload.status(
          isError: false,
          title: 'Настройки',
          statusText: screen.name,
        ),
    };
    return base.copyWithStatusIcons(
      wifiAvailable:
          controls.connectivity.phase == WearConnectivityPhase.online,
      showPrinterIcon: features.printer.selection != null,
      printerAvailable: features.printer.selection != null,
      voiceCommandsEnabled: controls.voice.commandsEnabled,
    );
  }

  static WearGlassesPayload _printer(WearPrinterTaskSlice task) {
    if (task.isLoading) {
      return WearGlassesPayload.loading(
        screenType: WearGlassesScreenType.printer,
        title: 'Выбор принтера',
        statusText: 'Инициализация...',
      );
    }
    if (task.error != null || task.visiblePrinters.isEmpty) {
      return WearGlassesPayload.status(
        isError: true,
        title: 'Принтеры',
        statusText: task.error ?? 'Список принтеров пуст',
      );
    }
    final printers = task.visiblePrinters;
    final int selected = task.focusedIndex.clamp(0, printers.length - 1);
    final int start = selected ~/ 4 * 4;
    final visible = printers.skip(start).take(4).toList(growable: false);
    return WearGlassesPayload(
      screenType: WearGlassesScreenType.printer,
      phase: WearGlassesPhase.idle,
      title: 'Выбор принтера',
      subtitle: task.step == WearPrinterTaskStep.yellow
          ? 'Жёлтые ценники'
          : 'Белые ценники',
      items: visible.map((item) => item.name).toList(growable: false),
      selectedIndex: selected - start,
      pageText: printers.length > 4
          ? 'Страница: ${selected ~/ 4 + 1} из ${(printers.length + 3) ~/ 4}'
          : null,
    );
  }

  static WearGlassesPayload _scan(WearScanTaskSlice task) {
    switch (task.phase) {
      case WearScanTaskPhase.waiting:
        return WearGlassesPayload.scanWaiting();
      case WearScanTaskPhase.lookingUp:
        return WearGlassesPayload.loading(
          screenType: WearGlassesScreenType.scan,
          title: 'Сканирование товара',
          statusText: 'ШК отсканирован, распознаю...',
          statusIcon: WearImages.barcode,
        );
      case WearScanTaskPhase.printing:
        return WearGlassesPayload.printing(productName: task.productName);
      case WearScanTaskPhase.status:
        final status = task.status;
        return WearGlassesPayload.status(
          isError: status?.kind.name == 'error',
          title: status?.title ?? 'Статус',
          subtitle: status?.message,
          statusText: status?.glassesStatusText,
          statusIcon: status?.glassesStatusIcon,
        );
      case WearScanTaskPhase.selecting:
        final products = task.products;
        if (products.isEmpty) {
          return WearGlassesPayload.status(
            isError: true,
            title: 'Выбор товара',
            statusText: 'Список товаров пуст',
          );
        }
        final int selected = task.focusedIndex.clamp(0, products.length - 1);
        final int start = selected ~/ 4 * 4;
        return WearGlassesPayload(
          screenType: WearGlassesScreenType.productSelect,
          phase: WearGlassesPhase.idle,
          title: 'Выбор товара',
          items: products
              .skip(start)
              .take(4)
              .map((item) => item.name)
              .toList(growable: false),
          selectedIndex: selected - start,
          pageText: products.length > 4
              ? 'Страница: ${selected ~/ 4 + 1} из ${(products.length + 3) ~/ 4}'
              : null,
        );
    }
  }

  static WearGlassesPayload _availability(WearAvailabilityTaskSlice task) {
    if (task.isBusy) {
      return WearAvailabilityGlassesPayloads.loading(title: 'Доступность');
    }
    if (task.error != null) {
      return WearAvailabilityGlassesPayloads.error(
        title: 'Ошибка доступности',
        message: task.error,
      );
    }
    if (task.isDuplicateSelection) {
      return WearAvailabilityGlassesPayloads.duplicates(
        task.flow.duplicateProducts,
        selectedIndex: task.focusedIndex,
      );
    }
    if (task.screen == WearScreenId.availabilityDirectScan) {
      return WearAvailabilityGlassesPayloads.directScanWaiting(
        statusText: task.flow.message ?? 'Поиск ШК...',
      );
    }
    if (task.screen == WearScreenId.availabilityFill) {
      return WearGlassesPayload(
        screenType: WearGlassesScreenType.availability,
        phase: WearGlassesPhase.idle,
        title: 'Наполнение базы',
        statusText: task.message ?? 'Сканируйте товары с полки',
        bodyLines: <String>['Добавлено: ${task.savedCount}'],
      );
    }
    if (task.screen == WearScreenId.availabilityGroup) {
      return WearAvailabilityGlassesPayloads.groups(
        task.flow.groups,
        selectedIndex: task.focusedIndex,
      );
    }
    if (task.screen == WearScreenId.availabilityProduct) {
      final WearAvailabilityGroup? group = task.flow.selectedGroup;
      if (group == null) {
        return WearAvailabilityGlassesPayloads.error(
          title: 'Доступность',
          message: 'Не выбрана товарная группа',
        );
      }
      return _availabilityProducts(group, task.flow.products, task.focusedIndex);
    }
    return WearAvailabilityGlassesPayloads.fromFlow(task.flow);
  }

  static WearGlassesPayload _availabilityProducts(
    WearAvailabilityGroup group,
    List<WearAvailabilityProduct> products,
    int focusedIndex,
  ) {
    if (products.isEmpty) {
      return WearGlassesPayload(
        screenType: WearGlassesScreenType.availability,
        phase: WearGlassesPhase.idle,
        title: group.name,
        statusText: 'В группе нет заданий',
      );
    }
    final int selected = focusedIndex.clamp(0, products.length - 1);
    final int start = selected ~/ 4 * 4;
    return WearGlassesPayload(
      screenType: WearGlassesScreenType.availability,
      phase: WearGlassesPhase.idle,
      title: 'Товарная позиция',
      subtitle: group.name,
      items: products
          .skip(start)
          .take(4)
          .map((item) => '${item.name} · ост. ${item.rest}')
          .toList(growable: false),
      selectedIndex: selected - start,
      pageText: products.length > 4
          ? 'Страница: ${selected ~/ 4 + 1} из ${(products.length + 3) ~/ 4}'
          : null,
    );
  }
}
