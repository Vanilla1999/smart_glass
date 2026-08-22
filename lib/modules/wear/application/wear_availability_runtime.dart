import 'dart:async';

import 'package:smart_glasses/modules/wear/application/wear_background_runtime.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_flow_state.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_group.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/domain/availability/use_case/wear_availability_flow_use_case.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_list_matcher.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_availability_glasses_payloads.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

typedef WearAvailabilityNavigation = Future<void> Function(
  WearScreenId screen, {
  Object? extra,
  bool replaceCurrent,
});
typedef WearAvailabilityPhotoCapture = Future<void> Function();
typedef WearAvailabilityPrint = Future<String> Function(
  WearAvailabilityProduct product,
);
typedef WearAvailabilityFillAdd = Future<List<WearAvailabilityProduct>>
    Function(
  String barcode,
);
typedef WearAvailabilityFillReset = Future<void> Function();

class WearAvailabilityRuntimeState {
  const WearAvailabilityRuntimeState({
    required this.flow,
    required this.focusedIndex,
    this.busy = false,
    this.error,
    this.savedCount = 0,
    this.message,
  });

  final WearAvailabilityFlowState flow;
  final int focusedIndex;
  final bool busy;
  final String? error;
  final int savedCount;
  final String? message;

  List<WearAvailabilityGroup> get groups => flow.groups;
  List<WearAvailabilityProduct> get products => flow.products;
  List<WearAvailabilityProduct> get duplicateProducts => flow.duplicateProducts;
}

class WearAvailabilityRuntime implements WearBackgroundRuntime {
  WearAvailabilityRuntime({
    required WearAvailabilityFlowUseCase flowUseCase,
    required WearAvailabilityNavigation navigate,
    required WearAvailabilityPhotoCapture capturePhoto,
    required WearAvailabilityPrint printPriceTag,
    WearAvailabilityFillAdd? fillAdd,
    WearAvailabilityFillReset? fillReset,
  })  : _flowUseCase = flowUseCase,
        _navigate = navigate,
        _capturePhoto = capturePhoto,
        _printPriceTag = printPriceTag,
        _fillAdd = fillAdd ?? _emptyFillAdd,
        _fillReset = fillReset ?? _emptyFillReset;

  static Future<List<WearAvailabilityProduct>> _emptyFillAdd(String _) async =>
      const <WearAvailabilityProduct>[];

  static Future<void> _emptyFillReset() async {}

  static const int _pageSize = 4;
  static const Set<WearScreenId> _screens = <WearScreenId>{
    WearScreenId.availabilityGroup,
    WearScreenId.availabilityProduct,
    WearScreenId.availabilityDirectScan,
    WearScreenId.availabilityCheck,
    WearScreenId.availabilityFill,
  };

  final WearAvailabilityFlowUseCase _flowUseCase;
  final WearAvailabilityNavigation _navigate;
  final WearAvailabilityPhotoCapture _capturePhoto;
  final WearAvailabilityPrint _printPriceTag;
  final WearAvailabilityFillAdd _fillAdd;
  final WearAvailabilityFillReset _fillReset;
  final StreamController<WearBackgroundScreenUpdate> _updates =
      StreamController<WearBackgroundScreenUpdate>.broadcast();
  final StreamController<WearAvailabilityRuntimeState> _stateController =
      StreamController<WearAvailabilityRuntimeState>.broadcast();

  WearAvailabilityFlowState? _flow;
  WearScreenId _screen = WearScreenId.availabilityGroup;
  int _focusedIndex = 0;
  bool _loading = false;
  String? _error;
  String? _lastBarcode;
  WearAvailabilityFlowStep? _lastBarcodeStep;
  int _generation = 0;
  int _requestRevision = 0;
  int _savedCount = 0;
  String? _message;
  Future<void>? _enterOperation;
  WearScreenId? _enteringScreen;
  Object? _enteringExtra;

  @override
  Stream<WearBackgroundScreenUpdate> get updates => _updates.stream;

  WearAvailabilityRuntimeState get state => WearAvailabilityRuntimeState(
        flow: _flow ??
            const WearAvailabilityFlowState(
              step: WearAvailabilityFlowStep.groupSelection,
            ),
        focusedIndex: _focusedIndex,
        busy: _loading,
        error: _error,
        savedCount: _savedCount,
        message: _message ?? _flow?.message,
      );

  Stream<WearAvailabilityRuntimeState> get stateStream =>
      _stateController.stream;

  @override
  bool handles(WearScreenId screen) => _screens.contains(screen);

  @override
  bool acceptsBarcode(WearScreenId screen) {
    if (_loading) return false;
    if (screen == WearScreenId.availabilityDirectScan) {
      return _flow?.duplicateProducts.isEmpty ?? true;
    }
    if (screen == WearScreenId.availabilityFill) return true;
    if (screen != WearScreenId.availabilityCheck) return false;
    final WearAvailabilityFlowStep? step = _flow?.step;
    return step == WearAvailabilityFlowStep.productScan ||
        step == WearAvailabilityFlowStep.priceTagScan;
  }

  @override
  bool supportsCommand(WearScreenId screen, WearVoiceCommand command) {
    if (!handles(screen) || _loading) return false;
    if (screen == WearScreenId.availabilityFill) {
      return command == WearVoiceCommand.down ||
          command == WearVoiceCommand.clear;
    }
    if (screen == WearScreenId.availabilityCheck) {
      if (command == WearVoiceCommand.backToList) return true;
      return switch (_flow?.step) {
        WearAvailabilityFlowStep.productQuestion =>
          command == WearVoiceCommand.yes || command == WearVoiceCommand.no,
        WearAvailabilityFlowStep.priceTagOutdated =>
          command == WearVoiceCommand.print,
        WearAvailabilityFlowStep.photoCapture =>
          command == WearVoiceCommand.takePhoto,
        WearAvailabilityFlowStep.readyToComplete ||
        WearAvailabilityFlowStep.manualInventoryRequired =>
          command == WearVoiceCommand.finish ||
              command == WearVoiceCommand.select,
        _ => false,
      };
    }
    if (screen != WearScreenId.availabilityGroup &&
        screen != WearScreenId.availabilityProduct &&
        !_isDuplicateSelection) {
      return false;
    }
    if (_listValues.isEmpty) return false;
    return <WearVoiceCommand>{
      WearVoiceCommand.up,
      WearVoiceCommand.down,
      WearVoiceCommand.select,
      WearVoiceCommand.nextPage,
      WearVoiceCommand.previousPage,
    }.contains(command);
  }

  @override
  Future<void> enterScreen(WearScreenId screen, {Object? extra}) async {
    if (!handles(screen)) return;
    if (_enterOperation != null &&
        _enteringScreen == screen &&
        identical(_enteringExtra, extra)) {
      return _enterOperation;
    }
    _enteringScreen = screen;
    _enteringExtra = extra;
    final int requestRevision = ++_requestRevision;
    final Future<void> operation = _enterScreen(
      screen,
      extra: extra,
      requestRevision: requestRevision,
    );
    _enterOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_enterOperation, operation)) {
        _enterOperation = null;
        _enteringScreen = null;
        _enteringExtra = null;
      }
    }
  }

  Future<void> _enterScreen(
    WearScreenId screen, {
    Object? extra,
    required int requestRevision,
  }) async {
    final int generation = _generation;
    if (!_isCurrent(generation, requestRevision: requestRevision)) return;
    if (_screen != screen) {
      _lastBarcode = null;
      _lastBarcodeStep = null;
    }
    _screen = screen;
    _focusedIndex = 0;
    _loading = false;
    _error = null;
    try {
      if (screen == WearScreenId.availabilityGroup && _flow == null) {
        await _runLoading(
          (int operationGeneration) async {
            final WearAvailabilityFlowState next = await _flowUseCase.start();
            if (_isCurrent(
              operationGeneration,
              requestRevision: requestRevision,
            )) {
              _flow = next;
            }
          },
          requestRevision: requestRevision,
        );
        return;
      }
      if (screen == WearScreenId.availabilityFill) {
        _message ??= 'Сканируйте товары с полки';
      }
      if (screen == WearScreenId.availabilityProduct &&
          extra is WearAvailabilityGroup &&
          _flow?.selectedGroup?.id != extra.id) {
        await _runLoading(
          (int operationGeneration) async {
            final WearAvailabilityFlowState next =
                await _flowUseCase.selectGroup(
              state: _flow ?? await _flowUseCase.start(),
              group: extra,
            );
            if (_isCurrent(
              operationGeneration,
              requestRevision: requestRevision,
            )) {
              _flow = next;
            }
          },
          requestRevision: requestRevision,
        );
        return;
      }
      if (!_isCurrent(generation, requestRevision: requestRevision)) return;
      if (screen == WearScreenId.availabilityCheck &&
          extra is WearAvailabilityFlowState) {
        _flow = extra;
      } else if (screen == WearScreenId.availabilityCheck &&
          extra is WearAvailabilityProduct &&
          _flow?.selectedProduct?.id != extra.id) {
        _flow = _flowUseCase.selectProduct(
          state: _flow ??
              const WearAvailabilityFlowState(
                step: WearAvailabilityFlowStep.productSelection,
              ),
          product: extra,
        );
      }
      if (_isCurrent(generation, requestRevision: requestRevision)) _publish();
    } catch (error) {
      if (!_isCurrent(generation, requestRevision: requestRevision)) return;
      _error = _messageFor(error);
      _loading = false;
      _publish();
    }
  }

  Future<void> _runLoading(
    Future<void> Function(int generation) operation, {
    int? requestRevision,
  }) async {
    final int generation = _generation;
    if (!_isCurrent(generation, requestRevision: requestRevision)) return;
    _loading = true;
    _publish();
    try {
      await operation(generation);
    } finally {
      if (_isCurrent(generation, requestRevision: requestRevision)) {
        _loading = false;
        _publish();
      }
    }
  }

  @override
  Future<bool> handleCommand(
    WearScreenId screen,
    WearVoiceCommand command,
  ) async {
    if (!handles(screen) || _loading) return false;
    if (screen == WearScreenId.availabilityFill) {
      if (command != WearVoiceCommand.down &&
          command != WearVoiceCommand.clear) {
        return false;
      }
      await resetFill();
      return true;
    }
    final bool listScreen = screen == WearScreenId.availabilityGroup ||
        screen == WearScreenId.availabilityProduct ||
        _isDuplicateSelection;
    if (listScreen && _listValues.isNotEmpty) {
      switch (command) {
        case WearVoiceCommand.up:
          _move(-1);
          return true;
        case WearVoiceCommand.down:
          _move(1);
          return true;
        case WearVoiceCommand.nextPage:
          _move(_pageSize);
          return true;
        case WearVoiceCommand.previousPage:
          _move(-_pageSize);
          return true;
        case WearVoiceCommand.select:
          await _selectFocused();
          return true;
        default:
          break;
      }
    }
    if (screen != WearScreenId.availabilityCheck) return false;
    final WearAvailabilityFlowStep? step = _flow?.step;
    switch (command) {
      case WearVoiceCommand.yes:
        return _answerAvailable(true);
      case WearVoiceCommand.no:
        return _answerAvailable(false);
      case WearVoiceCommand.print:
        if (step != WearAvailabilityFlowStep.priceTagOutdated) return false;
        await _print();
        return true;
      case WearVoiceCommand.takePhoto:
        if (step != WearAvailabilityFlowStep.photoCapture) return false;
        await _takePhoto();
        return true;
      case WearVoiceCommand.finish:
      case WearVoiceCommand.select:
        if (step != WearAvailabilityFlowStep.readyToComplete &&
            step != WearAvailabilityFlowStep.manualInventoryRequired) {
          return false;
        }
        await _complete();
        return true;
      case WearVoiceCommand.backToList:
        await _navigate(WearScreenId.availabilityGroup);
        return true;
      default:
        return false;
    }
  }

  @override
  Future<bool> handlePhrase(WearScreenId screen, String phrase) async {
    if (!handles(screen) || _loading) return false;
    final List<Object> values = _listValues;
    if (values.isEmpty) return false;
    final VoiceListMatch<Object> match = VoiceListMatcher.match(
      phrase,
      values,
      _labelFor,
    );
    if (match.type != VoiceListMatchType.unique) return false;
    await _select(match.item!);
    return true;
  }

  @override
  Future<bool> handleDynamicItem(WearScreenId screen, String itemId) async {
    if (!handles(screen) || _loading) return false;
    for (final Object value in _listValues) {
      if (_idFor(value) != itemId) continue;
      await _select(value);
      return true;
    }
    return false;
  }

  @override
  Future<bool> handleBarcode(WearScreenId screen, String barcode) async {
    if (!handles(screen) || !acceptsBarcode(screen)) return false;
    final String value = barcode.trim();
    if (value.isEmpty) return false;
    final WearAvailabilityFlowState flow = _flow ??
        const WearAvailabilityFlowState(
          step: WearAvailabilityFlowStep.productSelection,
        );
    if (_lastBarcode == value && _lastBarcodeStep == flow.step) return true;
    _lastBarcode = value;
    _lastBarcodeStep = flow.step;
    if (screen == WearScreenId.availabilityFill) {
      final int generation = _generation;
      final int requestRevision = _requestRevision;
      try {
        await _runLoading(
          (int operationGeneration) async {
            final List<WearAvailabilityProduct> products =
                await _fillAdd(value);
            if (_isCurrent(
              operationGeneration,
              requestRevision: requestRevision,
            )) {
              _savedCount += products.length;
              _message = products.length == 1
                  ? 'Добавлено: ${products.first.name}'
                  : 'Добавлено позиций: ${products.length}';
            }
          },
          requestRevision: requestRevision,
        );
      } catch (error) {
        if (!_isCurrent(generation, requestRevision: requestRevision)) {
          return true;
        }
        _lastBarcode = null;
        _lastBarcodeStep = null;
        _error = _messageFor(error);
        _message = _error;
        _loading = false;
        _publish();
      }
      return true;
    }
    if (screen == WearScreenId.availabilityDirectScan) {
      final int generation = _generation;
      final int requestRevision = _requestRevision;
      try {
        await _runLoading(
          (int operationGeneration) async {
            final WearAvailabilityFlowState next =
                await _flowUseCase.findProductByBarcode(flow, barcode: value);
            if (_isCurrent(
              operationGeneration,
              requestRevision: requestRevision,
            )) {
              _flow = next;
            }
          },
          requestRevision: requestRevision,
        );
      } catch (error) {
        if (!_isCurrent(generation, requestRevision: requestRevision)) {
          return true;
        }
        _lastBarcode = null;
        _lastBarcodeStep = null;
        _error = _messageFor(error);
        _loading = false;
        _publish();
        return true;
      }
      final WearAvailabilityProduct? product = _flow?.selectedProduct;
      if (_isCurrent(generation, requestRevision: requestRevision) &&
          product != null &&
          _flow?.step == WearAvailabilityFlowStep.productQuestion) {
        await _navigate(WearScreenId.availabilityCheck, extra: product);
      }
      return true;
    }
    if (screen != WearScreenId.availabilityCheck) return false;
    if (flow.step == WearAvailabilityFlowStep.productScan) {
      _flow = _flowUseCase.scanProductBarcode(state: flow, barcode: value);
      _publish();
      return true;
    }
    if (flow.step == WearAvailabilityFlowStep.priceTagScan) {
      _flow = _flowUseCase.scanPriceTagBarcode(state: flow, barcode: value);
      _publish();
      return true;
    }
    return false;
  }

  bool _answerAvailable(bool available) {
    final WearAvailabilityFlowState? flow = _flow;
    if (flow == null || flow.step != WearAvailabilityFlowStep.productQuestion) {
      return false;
    }
    _flow = _flowUseCase.answerProductAvailable(flow, available: available);
    _publish();
    return true;
  }

  void focus(int index) {
    final int count = _listValues.length;
    if (count == 0) return;
    final int next = index.clamp(0, count - 1);
    if (next == _focusedIndex) return;
    _focusedIndex = next;
    _publish();
  }

  Future<void> select(Object value) => _select(value);

  bool answerAvailable(bool available) => _answerAvailable(available);

  Future<void> printPriceTag() => _print();

  Future<void> takePhoto() => _takePhoto();

  Future<void> complete() => _complete();

  Future<void> resetFill() async {
    if (_loading || _screen != WearScreenId.availabilityFill) return;
    final int generation = _generation;
    final int requestRevision = _requestRevision;
    try {
      await _runLoading(
        (int operationGeneration) async {
          await _fillReset();
          if (_isCurrent(
            operationGeneration,
            requestRevision: requestRevision,
          )) {
            _savedCount = 0;
            _lastBarcode = null;
            _lastBarcodeStep = null;
            _message = 'База сканированной полки очищена';
            _error = null;
          }
        },
        requestRevision: requestRevision,
      );
    } catch (error) {
      if (!_isCurrent(generation, requestRevision: requestRevision)) return;
      _error = _messageFor(error);
      _message = _error;
      _loading = false;
      _publish();
    }
  }

  Future<void> _print() async {
    final WearAvailabilityFlowState? flow = _flow;
    final WearAvailabilityProduct? product = flow?.selectedProduct;
    if (flow == null ||
        product == null ||
        flow.step != WearAvailabilityFlowStep.priceTagOutdated) {
      return;
    }
    final int requestRevision = _requestRevision;
    await _runLoading(
      (int generation) async {
        final String printer = await _printPriceTag(product);
        final WearAvailabilityFlowState next = _flowUseCase.markPriceTagPrinted(
          state: flow,
          printerName: printer,
        );
        if (_isCurrent(generation, requestRevision: requestRevision)) {
          _flow = next;
        }
      },
      requestRevision: requestRevision,
    );
  }

  Future<void> _takePhoto() async {
    final WearAvailabilityFlowState? flow = _flow;
    if (flow == null || flow.step != WearAvailabilityFlowStep.photoCapture) {
      return;
    }
    final int generation = _generation;
    final int requestRevision = _requestRevision;
    try {
      await _runLoading(
        (int operationGeneration) async {
          await _capturePhoto();
          if (_isCurrent(
            operationGeneration,
            requestRevision: requestRevision,
          )) {
            _flow = _flowUseCase.capturePhoto(flow);
          }
        },
        requestRevision: requestRevision,
      );
    } catch (error) {
      if (!_isCurrent(generation, requestRevision: requestRevision)) return;
      _error = _messageFor(error);
      _loading = false;
      _publish();
    }
  }

  Future<void> _complete() async {
    final WearAvailabilityFlowState? flow = _flow;
    if (flow == null ||
        flow.step != WearAvailabilityFlowStep.readyToComplete &&
            flow.step != WearAvailabilityFlowStep.manualInventoryRequired) {
      return;
    }
    final int generation = _generation;
    final int requestRevision = _requestRevision;
    await _runLoading(
      (int operationGeneration) async {
        final WearAvailabilityFlowState next =
            await _flowUseCase.complete(flow);
        if (_isCurrent(
          operationGeneration,
          requestRevision: requestRevision,
        )) {
          _flow = next;
        }
      },
      requestRevision: requestRevision,
    );
    if (!_isCurrent(generation, requestRevision: requestRevision)) return;
    await _navigate(WearScreenId.availabilityGroup, replaceCurrent: true);
  }

  void _move(int delta) {
    final int count = _listValues.length;
    if (count == 0) return;
    _focusedIndex = (_focusedIndex + delta).clamp(0, count - 1);
    _publish();
  }

  Future<void> _selectFocused() async {
    final List<Object> values = _listValues;
    if (values.isEmpty) return;
    await _select(values[_focusedIndex.clamp(0, values.length - 1)]);
  }

  Future<void> _select(Object value) async {
    final WearAvailabilityFlowState? flow = _flow;
    if (flow == null) return;
    if (value is WearAvailabilityGroup) {
      final int generation = _generation;
      final int requestRevision = _requestRevision;
      await _runLoading(
        (int operationGeneration) async {
          final WearAvailabilityFlowState next =
              await _flowUseCase.selectGroup(state: flow, group: value);
          if (_isCurrent(
            operationGeneration,
            requestRevision: requestRevision,
          )) {
            _flow = next;
          }
        },
        requestRevision: requestRevision,
      );
      if (!_isCurrent(generation, requestRevision: requestRevision)) return;
      await _navigate(WearScreenId.availabilityProduct, extra: value);
      return;
    }
    if (value is WearAvailabilityProduct) {
      final bool directDuplicate = _isDuplicateSelection;
      _flow = directDuplicate && flow.lastBarcode != null
          ? _flowUseCase.selectScannedProduct(
              state: flow,
              product: value,
              barcode: flow.lastBarcode!,
            )
          : _flowUseCase.selectProduct(state: flow, product: value);
      _publish();
      await _navigate(
        WearScreenId.availabilityCheck,
        extra: directDuplicate ? _flow : value,
      );
    }
  }

  bool get _isDuplicateSelection =>
      _screen == WearScreenId.availabilityDirectScan &&
      _flow?.step == WearAvailabilityFlowStep.duplicateSelection;

  List<Object> get _listValues {
    final WearAvailabilityFlowState? flow = _flow;
    if (flow == null) return const <Object>[];
    if (_screen == WearScreenId.availabilityGroup) return flow.groups;
    if (_screen == WearScreenId.availabilityProduct) return flow.products;
    if (_isDuplicateSelection) return flow.duplicateProducts;
    return const <Object>[];
  }

  @override
  VoiceDynamicItemsSnapshot dynamicVoiceItemsFor(WearScreenId screen) {
    if (!handles(screen)) return VoiceDynamicItemsSnapshot.empty;
    final List<VoiceDynamicItem> items = _listValues
        .map(
          (Object value) => VoiceDynamicItem(
            id: _idFor(value),
            label: _labelFor(value),
          ),
        )
        .toList(growable: false);
    return VoiceDynamicItemsSnapshot(
      revision: Object.hashAll(
        items.map((VoiceDynamicItem item) => item.revisionHash),
      ),
      items: items,
    );
  }

  @override
  void restorePresentationState(WearScreenId screen, Object state) {}

  @override
  Object? presentationStateFor(WearScreenId screen) => null;

  String _idFor(Object value) => switch (value) {
        WearAvailabilityGroup group => group.id.toString(),
        WearAvailabilityProduct product => product.id.toString(),
        _ => '',
      };

  String _labelFor(Object value) => switch (value) {
        WearAvailabilityGroup group => group.name,
        WearAvailabilityProduct product => product.name,
        _ => '',
      };

  bool _isCurrent(int generation, {int? requestRevision}) {
    return generation == _generation &&
        (requestRevision == null || requestRevision == _requestRevision);
  }

  void _publish() {
    if (!_stateController.isClosed) _stateController.add(state);
    if (_updates.isClosed) return;
    _updates.add(
      WearBackgroundScreenUpdate(screen: _screen, payload: _payload()),
    );
  }

  WearGlassesPayload _payload() {
    if (_loading) {
      return WearAvailabilityGlassesPayloads.loading(
        title: _screen == WearScreenId.availabilityGroup
            ? 'Товарная группа'
            : 'Доступность',
      );
    }
    if (_error != null) {
      return WearAvailabilityGlassesPayloads.error(
        title: 'Ошибка доступности',
        message: _error,
      );
    }
    final WearAvailabilityFlowState? flow = _flow;
    if (_isDuplicateSelection && flow != null) {
      return WearAvailabilityGlassesPayloads.duplicates(
        flow.duplicateProducts,
        selectedIndex: _focusedIndex,
      );
    }
    if (_screen == WearScreenId.availabilityDirectScan) {
      return WearAvailabilityGlassesPayloads.directScanWaiting(
        statusText: flow?.message ?? 'Поиск ШК...',
      );
    }
    if (_screen == WearScreenId.availabilityFill) {
      return WearGlassesPayload(
        screenType: WearGlassesScreenType.availability,
        phase: WearGlassesPhase.idle,
        title: 'Наполнение базы',
        statusText: _message ?? 'Сканируйте товары с полки',
        bodyLines: <String>['Добавлено: $_savedCount'],
      );
    }
    if (flow == null) {
      return WearAvailabilityGlassesPayloads.loading(title: 'Доступность');
    }
    if (_screen == WearScreenId.availabilityGroup) {
      return WearAvailabilityGlassesPayloads.groups(
        flow.groups,
        selectedIndex: _focusedIndex,
      );
    }
    if (_screen == WearScreenId.availabilityProduct) {
      final WearAvailabilityGroup? group = flow.selectedGroup;
      if (group == null) {
        return WearAvailabilityGlassesPayloads.error(
          title: 'Доступность',
          message: 'Не выбрана товарная группа',
        );
      }
      return WearAvailabilityGlassesPayloads.products(
        group: group,
        products: flow.products,
        voiceSnapshot: dynamicVoiceItemsFor(_screen),
        selectedIndex: _focusedIndex,
      );
    }
    return WearAvailabilityGlassesPayloads.fromFlow(flow);
  }

  String _messageFor(Object error) {
    final String message = error.toString();
    return message.startsWith('Exception: ')
        ? message.substring('Exception: '.length)
        : message;
  }

  @override
  Future<void> reset() async {
    _generation += 1;
    _requestRevision += 1;
    _enterOperation = null;
    _enteringScreen = null;
    _enteringExtra = null;
    _flow = null;
    _screen = WearScreenId.availabilityGroup;
    _focusedIndex = 0;
    _loading = false;
    _error = null;
    _lastBarcode = null;
    _lastBarcodeStep = null;
    _savedCount = 0;
    _message = null;
  }

  @override
  Future<void> dispose() async {
    await reset();
    await _stateController.close();
    await _updates.close();
  }
}
