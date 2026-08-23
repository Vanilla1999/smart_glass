import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_flow_state.dart';
import 'package:smart_glasses/modules/wear/domain/availability/model/wear_availability_product.dart';
import 'package:smart_glasses/modules/wear/domain/availability/use_case/wear_availability_flow_use_case.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_availability_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_effect_router.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

typedef WearAvailabilityEffectNavigation = Future<void> Function(
  WearScreenId screen, {
  Object? extra,
  bool replaceCurrent,
});
typedef WearAvailabilityEffectPhotoCapture = Future<void> Function();
typedef WearAvailabilityEffectPrint = Future<String> Function(
  WearAvailabilityProduct product,
);
typedef WearAvailabilityEffectFillAdd =
    Future<List<WearAvailabilityProduct>> Function(String barcode);
typedef WearAvailabilityEffectFillReset = Future<void> Function();

class WearAvailabilityEffectExecutor
    implements WearEffectExecutor, WearEffectExecutorLease {
  WearAvailabilityEffectExecutor({
    required WearAvailabilityFlowUseCase flowUseCase,
    required WearAvailabilityEffectNavigation navigate,
    required WearAvailabilityEffectPhotoCapture capturePhoto,
    required WearAvailabilityEffectPrint printPriceTag,
    required WearAvailabilityEffectFillAdd fillAdd,
    required WearAvailabilityEffectFillReset fillReset,
  })  : _flowUseCase = flowUseCase,
        _navigate = navigate,
        _capturePhoto = capturePhoto,
        _printPriceTag = printPriceTag,
        _fillAdd = fillAdd,
        _fillReset = fillReset;

  static const String domainKey = 'availability';

  final WearAvailabilityFlowUseCase _flowUseCase;
  final WearAvailabilityEffectNavigation _navigate;
  final WearAvailabilityEffectPhotoCapture _capturePhoto;
  final WearAvailabilityEffectPrint _printPriceTag;
  final WearAvailabilityEffectFillAdd _fillAdd;
  final WearAvailabilityEffectFillReset _fillReset;
  bool _active = true;

  @override
  String get registrationKey => domainKey;

  @override
  bool get isActive => _active;

  @override
  void deactivate() {
    _active = false;
  }

  @override
  bool handles(WearEffect effect) {
    return _active && effect is WearAvailabilityOperationEffect;
  }

  @override
  Future<WearIntent?> execute(WearEffect rawEffect) async {
    final WearAvailabilityOperationEffect effect =
        rawEffect as WearAvailabilityOperationEffect;
    try {
      WearAvailabilityFlowState flow = effect.flow;
      int addedCount = 0;
      String? message;
      switch (effect.operation) {
        case WearAvailabilityOperation.start:
          flow = await _flowUseCase.start();
          break;
        case WearAvailabilityOperation.selectGroup:
          final group = effect.group;
          if (group == null) throw StateError('Не выбрана товарная группа');
          flow = await _flowUseCase.selectGroup(state: flow, group: group);
          break;
        case WearAvailabilityOperation.selectProduct:
          final product = effect.product;
          if (product == null) throw StateError('Не выбрана товарная позиция');
          flow = _flowUseCase.selectProduct(state: flow, product: product);
          break;
        case WearAvailabilityOperation.selectScannedProduct:
          final product = effect.product;
          final barcode = effect.barcode;
          if (product == null || barcode == null || barcode.isEmpty) {
            throw StateError('Не хватает данных выбранного ШК');
          }
          flow = _flowUseCase.selectScannedProduct(
            state: flow,
            product: product,
            barcode: barcode,
          );
          break;
        case WearAvailabilityOperation.findBarcode:
          final barcode = effect.barcode;
          if (barcode == null || barcode.isEmpty) {
            throw StateError('Пустой штрихкод');
          }
          flow = await _flowUseCase.findProductByBarcode(
            flow,
            barcode: barcode,
          );
          break;
        case WearAvailabilityOperation.answer:
          final available = effect.available;
          if (available == null) throw StateError('Не указан ответ');
          flow = _flowUseCase.answerProductAvailable(
            flow,
            available: available,
          );
          break;
        case WearAvailabilityOperation.scanProduct:
          final barcode = effect.barcode;
          if (barcode == null || barcode.isEmpty) {
            throw StateError('Пустой штрихкод товара');
          }
          flow = _flowUseCase.scanProductBarcode(
            state: flow,
            barcode: barcode,
          );
          break;
        case WearAvailabilityOperation.scanPriceTag:
          final barcode = effect.barcode;
          if (barcode == null || barcode.isEmpty) {
            throw StateError('Пустой штрихкод ценника');
          }
          flow = _flowUseCase.scanPriceTagBarcode(
            state: flow,
            barcode: barcode,
          );
          break;
        case WearAvailabilityOperation.printPriceTag:
          final WearAvailabilityProduct? product = flow.selectedProduct;
          if (product == null) throw StateError('Не выбрана товарная позиция');
          final String printer = await _printPriceTag(product);
          flow = _flowUseCase.markPriceTagPrinted(
            state: flow,
            printerName: printer,
          );
          break;
        case WearAvailabilityOperation.capturePhoto:
          await _capturePhoto();
          flow = _flowUseCase.capturePhoto(flow);
          break;
        case WearAvailabilityOperation.complete:
          await _flowUseCase.complete(flow);
          // Completion mutates the repository. Reload groups before publishing
          // the group screen so counters cannot be projected from stale state.
          flow = await _flowUseCase.start();
          break;
        case WearAvailabilityOperation.fillAdd:
          final barcode = effect.barcode;
          if (barcode == null || barcode.isEmpty) {
            throw StateError('Пустой штрихкод наполнения');
          }
          final List<WearAvailabilityProduct> products = await _fillAdd(barcode);
          addedCount = products.length;
          message = products.length == 1
              ? 'Добавлено: ${products.first.name}'
              : 'Добавлено позиций: ${products.length}';
          break;
        case WearAvailabilityOperation.fillReset:
          await _fillReset();
          message = 'База сканированной полки очищена';
          break;
        case WearAvailabilityOperation.navigate:
          final WearScreenId? target = effect.targetScreen;
          if (target == null) throw StateError('Не задан экран навигации');
          await _navigate(
            target,
            extra: effect.navigationExtra,
            replaceCurrent: effect.replaceCurrent,
          );
          break;
      }
      return WearAvailabilityOperationSucceeded(
        sessionEpoch: effect.sessionEpoch,
        operationId: effect.operationId,
        operation: effect.operation,
        flow: freezeAvailabilityFlow(flow),
        addedCount: addedCount,
        message: message,
      );
    } catch (error) {
      return WearAvailabilityOperationFailed(
        sessionEpoch: effect.sessionEpoch,
        operationId: effect.operationId,
        operation: effect.operation,
        message: _messageFor(error),
      );
    }
  }

  String _messageFor(Object error) {
    final String message = error.toString();
    return message.startsWith('Exception: ')
        ? message.substring('Exception: '.length)
        : message;
  }
}
