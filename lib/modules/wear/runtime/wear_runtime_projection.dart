import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_group.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_availability_glasses_payloads.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_voice_hints.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_availability_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_control_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_core_slices.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_dynamic_voice_items.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_printer_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_presentation_slice.dart';
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

  static WearGlassesEnvelope projectGlasses(
    WearRuntimeState state, {
    void Function()? onVoiceHintsPrepared,
  }) {
    final WearRuntimeControlPayload controls =
        _aggregate(state).controls as WearRuntimeControlPayload;
    return WearGlassesEnvelope(
      sessionEpoch: state.sessionEpoch,
      stateRevision: state.revision,
      logicalScreen: _aggregate(state).navigation.logicalScreen,
      payload: _payload(
        state,
        onVoiceHintsPrepared: onVoiceHintsPrepared,
      ),
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
        WearVoiceRuntimePhase.starting => 'Подготовка\nголосового управления',
        WearVoiceRuntimePhase.reconnecting =>
          'Переподключаем\nголосовое управление',
        WearVoiceRuntimePhase.unavailable => 'Голосовое управление недоступно',
        WearVoiceRuntimePhase.disabled || WearVoiceRuntimePhase.ready => null,
      },
    );
  }

  static WearAggregatePayload _aggregate(WearRuntimeState state) =>
      state.payloadAs<WearAggregatePayload>();

  static WearGlassesPayload _payload(
    WearRuntimeState state, {
    void Function()? onVoiceHintsPrepared,
  }) {
    final WearAggregatePayload aggregate = _aggregate(state);
    final WearScreenId screen = aggregate.navigation.logicalScreen;
    final WearRuntimeFeaturePayload features =
        aggregate.features as WearRuntimeFeaturePayload;
    final WearRuntimeControlPayload controls =
        aggregate.controls as WearRuntimeControlPayload;
    final WearRuntimePresentationSlice runtimePresentation =
        WearRuntimePresentationSlice.from(aggregate.presentation);
    final WearPresentationFocusSlice presentation = runtimePresentation;
    final WearGlassesPayload base = switch (screen) {
      WearScreenId.menu => WearGlassesPayload.menu(
          selectedIndex: presentation.focusFor(screen) ?? 0,
        ),
      WearScreenId.homeConfirm => WearGlassesPayload.homeConfirm(
          selectedIndex: presentation.focusFor(screen) ?? 0,
        ),
      WearScreenId.help => WearGlassesPayload.help(),
      WearScreenId.continueScan => WearGlassesPayload.continueScan(
          selectedIndex: presentation.focusFor(screen) ?? 0,
        ),
      WearScreenId.printerSelect => _printer(
          state,
          features.printer,
          onVoiceHintsPrepared,
        ),
      WearScreenId.scanIdle || WearScreenId.productSelect => _scan(
          state,
          features.scan as WearScanTaskSlice,
          onVoiceHintsPrepared,
        ),
      WearScreenId.status => runtimePresentation.statusArgs == null
          ? _scan(
              state,
              features.scan as WearScanTaskSlice,
              onVoiceHintsPrepared,
            )
          : _genericStatus(runtimePresentation.statusArgs!),
      WearScreenId.availabilityInteraction =>
        WearAvailabilityGlassesPayloads.interactionTypes(
          selectedIndex: presentation.focusFor(screen) ?? 0,
        ),
      WearScreenId.availabilityGroup ||
      WearScreenId.availabilityProduct ||
      WearScreenId.availabilityDirectScan ||
      WearScreenId.availabilityCheck ||
      WearScreenId.availabilityFill =>
        _availability(
          state,
          features.availability as WearAvailabilityTaskSlice,
          onVoiceHintsPrepared,
        ),
      WearScreenId.scannerConnect => WearGlassesPayload.loading(
          screenType: WearGlassesScreenType.status,
          title: 'Сканер',
          statusText: 'Подключение...',
        ),
      WearScreenId.main => WearGlassesPayload.authWaitingBarcode(),
      WearScreenId.voiceClarification => _voiceClarification(
          state,
          runtimePresentation,
          onVoiceHintsPrepared,
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
    final String? feedback = runtimePresentation.recognitionFeedbackFor(screen);
    final WearGlassesPayload content =
        feedback == null ? base : base.copyWithStatusText(feedback);
    return content.copyWithStatusIcons(
      wifiAvailable:
          controls.connectivity.phase == WearConnectivityPhase.online,
      showPrinterIcon: features.printer.selection != null,
      printerAvailable: features.printer.selection != null,
      voiceCommandsEnabled: controls.voice.commandsEnabled,
    );
  }

  static WearGlassesPayload _genericStatus(WearStatusScreenArgs args) {
    return WearGlassesPayload.status(
      isError: args.kind.name == 'error',
      title: args.title,
      subtitle: args.message,
      statusText: args.glassesStatusText ?? args.details,
      statusIcon: args.glassesStatusIcon,
    );
  }

  static WearGlassesPayload _voiceClarification(
    WearRuntimeState state,
    WearRuntimePresentationSlice presentation,
    void Function()? onVoiceHintsPrepared,
  ) {
    final args = presentation.clarificationArgs;
    final List<VoiceDynamicItem> matches =
        args?.matches ?? const <VoiceDynamicItem>[];
    if (matches.isEmpty) {
      return const WearGlassesPayload(
        screenType: WearGlassesScreenType.productSelect,
        phase: WearGlassesPhase.idle,
        title: 'Уточните фразу',
        statusText: 'Совпадения не найдены',
      );
    }
    const int pageSize = 4;
    final int selected =
        presentation.clarificationFocusedIndex.clamp(0, matches.length - 1);
    final int pageStart = (selected ~/ pageSize) * pageSize;
    final int page = (selected ~/ pageSize) + 1;
    final int pageCount = ((matches.length - 1) ~/ pageSize) + 1;
    final List<VoiceDynamicItem> visible =
        matches.skip(pageStart).take(pageSize).toList(growable: false);
    final VoiceDynamicItemsSnapshot snapshot =
        selectWearDynamicVoiceItems(state, WearScreenId.voiceClarification);
    return WearGlassesPayload(
      screenType: WearGlassesScreenType.productSelect,
      phase: WearGlassesPhase.idle,
      title: 'Уточните фразу',
      subtitle: args?.phrase,
      items: visible.map((item) => item.label).toList(growable: false),
      voiceHints: WearGlassesVoiceHints.forVisibleItems(
        screen: WearScreenId.voiceClarification,
        snapshot: snapshot,
        visibleItemIds: visible.map((item) => item.id).toList(growable: false),
        onPrepared: onVoiceHintsPrepared,
      ),
      selectedIndex: selected - pageStart,
      pageText: pageCount > 1 ? 'Страница: $page из $pageCount' : null,
      statusText: presentation.clarificationNotice,
    );
  }

  static WearGlassesPayload _printer(
    WearRuntimeState state,
    WearPrinterTaskSlice task,
    void Function()? onVoiceHintsPrepared,
  ) {
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
    final VoiceDynamicItemsSnapshot snapshot =
        selectWearDynamicVoiceItems(state, WearScreenId.printerSelect);
    return WearGlassesPayload(
      screenType: WearGlassesScreenType.printer,
      phase: WearGlassesPhase.idle,
      title: 'Выбор принтера',
      subtitle: task.step == WearPrinterTaskStep.yellow
          ? 'Жёлтые ценники'
          : 'Белые ценники',
      items: visible.map((item) => item.name).toList(growable: false),
      voiceHints: WearGlassesVoiceHints.forVisibleItems(
        screen: WearScreenId.printerSelect,
        snapshot: snapshot,
        visibleItemIds: visible.map((item) => item.id).toList(growable: false),
        onPrepared: onVoiceHintsPrepared,
      ),
      selectedIndex: selected - start,
      pageText: printers.length > 4
          ? 'Страница: ${selected ~/ 4 + 1} из ${(printers.length + 3) ~/ 4}'
          : null,
    );
  }

  static WearGlassesPayload _scan(
    WearRuntimeState state,
    WearScanTaskSlice task,
    void Function()? onVoiceHintsPrepared,
  ) {
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
        final visible = products.skip(start).take(4).toList(growable: false);
        final VoiceDynamicItemsSnapshot snapshot =
            selectWearDynamicVoiceItems(state, WearScreenId.productSelect);
        return WearGlassesPayload(
          screenType: WearGlassesScreenType.productSelect,
          phase: WearGlassesPhase.idle,
          title: 'Выбор товара',
          items: visible.map((item) => item.name).toList(growable: false),
          voiceHints: WearGlassesVoiceHints.forVisibleItems(
            screen: WearScreenId.productSelect,
            snapshot: snapshot,
            visibleItemIds: visible
                .map((item) => item.id.toString())
                .toList(growable: false),
            onPrepared: onVoiceHintsPrepared,
          ),
          selectedIndex: selected - start,
          pageText: products.length > 4
              ? 'Страница: ${selected ~/ 4 + 1} из ${(products.length + 3) ~/ 4}'
              : null,
        );
    }
  }

  static WearGlassesPayload _availability(
    WearRuntimeState state,
    WearAvailabilityTaskSlice task,
    void Function()? onVoiceHintsPrepared,
  ) {
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
        onVoiceHintsPrepared: onVoiceHintsPrepared,
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
        onVoiceHintsPrepared: onVoiceHintsPrepared,
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
      return _availabilityProducts(
        state,
        group,
        task.flow.products,
        task.focusedIndex,
        onVoiceHintsPrepared,
      );
    }
    return WearAvailabilityGlassesPayloads.fromFlow(task.flow);
  }

  static WearGlassesPayload _availabilityProducts(
    WearRuntimeState state,
    WearAvailabilityGroup group,
    List<WearAvailabilityProduct> products,
    int focusedIndex,
    void Function()? onVoiceHintsPrepared,
  ) {
    return WearAvailabilityGlassesPayloads.products(
      group: group,
      products: products,
      voiceSnapshot:
          selectWearDynamicVoiceItems(state, WearScreenId.availabilityProduct),
      selectedIndex: focusedIndex,
      onVoiceHintsPrepared: onVoiceHintsPrepared,
    );
  }
}
