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
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_availability_effects.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_availability_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

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
    Function(String barcode);
typedef WearAvailabilityFillReset = Future<void> Function();

class WearAvailabilityRuntimeState {
  const WearAvailabilityRuntimeState({
    required this.flow,
    required this.focusedIndex,
    required this.busy,
    required this.error,
    required this.savedCount,
    required this.message,
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
    WearRuntimeAuthority? authority,
  }) : _authority = authority ?? WearRuntimeAuthority() {
    _effectExecutor = WearAvailabilityEffectExecutor(
      flowUseCase: flowUseCase,
      navigate: navigate,
      capturePhoto: capturePhoto,
      printPriceTag: printPriceTag,
      fillAdd: fillAdd ?? _emptyFillAdd,
      fillReset: fillReset ?? _emptyFillReset,
    );
    _authority.registerEffectExecutor(_effectExecutor);
    _lastTask = _authority.availabilityTask;
    _subscription = _authority.states.listen(_onState);
  }

  static Future<List<WearAvailabilityProduct>> _emptyFillAdd(String _) async =>
      const <WearAvailabilityProduct>[];
  static Future<void> _emptyFillReset() async {}

  static const Set<WearScreenId> _screens = <WearScreenId>{
    WearScreenId.availabilityGroup,
    WearScreenId.availabilityProduct,
    WearScreenId.availabilityDirectScan,
    WearScreenId.availabilityCheck,
    WearScreenId.availabilityFill,
  };

  final WearRuntimeAuthority _authority;
  late final WearAvailabilityEffectExecutor _effectExecutor;
  final StreamController<WearBackgroundScreenUpdate> _updates =
      StreamController<WearBackgroundScreenUpdate>.broadcast();
  final StreamController<WearAvailabilityRuntimeState> _states =
      StreamController<WearAvailabilityRuntimeState>.broadcast();
  late final StreamSubscription<WearRuntimeState> _subscription;
  late WearAvailabilityTaskSlice _lastTask;
  bool _disposed = false;

  @override
  Stream<WearBackgroundScreenUpdate> get updates => _updates.stream;

  WearAvailabilityRuntimeState get state =>
      _mapState(_authority.availabilityTask);

  Stream<WearAvailabilityRuntimeState> get stateStream => _states.stream;

  @override
  bool handles(WearScreenId screen) => _screens.contains(screen);

  @override
  bool acceptsBarcode(WearScreenId screen) {
    return _authority.availabilityTask.acceptsBarcode(
      _authority.payload.navigation.logicalScreen,
    ) && _authority.availabilityTask.screen == screen;
  }

  @override
  bool supportsCommand(WearScreenId screen, WearVoiceCommand command) {
    final WearAvailabilityTaskSlice task = _authority.availabilityTask;
    if (task.isBusy || task.screen != screen ||
        _authority.payload.navigation.logicalScreen != screen) {
      return false;
    }
    if (screen == WearScreenId.availabilityFill) {
      return command == WearVoiceCommand.down ||
          command == WearVoiceCommand.clear;
    }
    if (screen == WearScreenId.availabilityCheck) {
      if (command == WearVoiceCommand.backToList) return true;
      return switch (task.flow.step) {
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
    if (task.listValues.isEmpty) return false;
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
    await _authority.enterAvailabilityScreen(screen, extra: extra);
  }

  @override
  Future<bool> handleCommand(
    WearScreenId screen,
    WearVoiceCommand command,
  ) async {
    if (!supportsCommand(screen, command)) return false;
    final WearDispatchResult result;
    switch (command) {
      case WearVoiceCommand.up:
        result = await _authority.moveAvailabilityFocus(-1);
        break;
      case WearVoiceCommand.down:
        if (screen == WearScreenId.availabilityFill) {
          result = await _authority.resetAvailabilityFill();
        } else {
          result = await _authority.moveAvailabilityFocus(1);
        }
        break;
      case WearVoiceCommand.nextPage:
        result = await _authority.moveAvailabilityPage(1);
        break;
      case WearVoiceCommand.previousPage:
        result = await _authority.moveAvailabilityPage(-1);
        break;
      case WearVoiceCommand.select:
        if (screen == WearScreenId.availabilityCheck) {
          result = await _authority.completeAvailability();
        } else {
          final WearAvailabilityTaskSlice task = _authority.availabilityTask;
          result = await _authority.selectAvailabilityItem(
            _idFor(task.listValues[task.focusedIndex]),
          );
        }
        break;
      case WearVoiceCommand.yes:
        result = await _authority.answerAvailability(true);
        break;
      case WearVoiceCommand.no:
        result = await _authority.answerAvailability(false);
        break;
      case WearVoiceCommand.print:
        result = await _authority.printAvailabilityPriceTag();
        break;
      case WearVoiceCommand.takePhoto:
        result = await _authority.captureAvailabilityPhoto();
        break;
      case WearVoiceCommand.finish:
        result = await _authority.completeAvailability();
        break;
      case WearVoiceCommand.clear:
        result = await _authority.resetAvailabilityFill();
        break;
      case WearVoiceCommand.backToList:
        result = await _authority.returnAvailabilityToList();
        break;
      default:
        return false;
    }
    return result.accepted;
  }

  @override
  Future<bool> handlePhrase(WearScreenId screen, String phrase) async {
    final WearAvailabilityTaskSlice task = _authority.availabilityTask;
    if (task.isBusy || task.screen != screen || task.listValues.isEmpty) {
      return false;
    }
    final VoiceListMatch<Object> match = VoiceListMatcher.match(
      phrase,
      task.listValues,
      _labelFor,
    );
    if (match.type != VoiceListMatchType.unique || match.item == null) {
      return false;
    }
    final WearDispatchResult result =
        await _authority.selectAvailabilityItem(_idFor(match.item!));
    return result.accepted;
  }

  @override
  Future<bool> handleDynamicItem(WearScreenId screen, String itemId) async {
    final WearAvailabilityTaskSlice task = _authority.availabilityTask;
    if (task.isBusy || task.screen != screen) return false;
    final WearDispatchResult result =
        await _authority.selectAvailabilityItem(itemId);
    return result.accepted;
  }

  @override
  Future<bool> handleBarcode(WearScreenId screen, String barcode) async {
    if (!acceptsBarcode(screen)) return false;
    final WearDispatchResult result =
        await _authority.submitAvailabilityBarcode(barcode);
    return result.accepted;
  }

  @override
  VoiceDynamicItemsSnapshot dynamicVoiceItemsFor(WearScreenId screen) {
    final WearAvailabilityTaskSlice task = _authority.availabilityTask;
    if (task.screen != screen) return VoiceDynamicItemsSnapshot.empty;
    final List<VoiceDynamicItem> items = task.listValues
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

  void focus(int index) {
    unawaited(_authority.focusAvailabilityItem(index));
  }

  Future<void> select(Object value) async {
    await _authority.selectAvailabilityItem(_idFor(value));
  }

  bool answerAvailable(bool available) {
    final WearAvailabilityTaskSlice task = _authority.availabilityTask;
    if (task.isBusy ||
        task.flow.step != WearAvailabilityFlowStep.productQuestion) {
      return false;
    }
    unawaited(_authority.answerAvailability(available));
    return true;
  }

  Future<void> printPriceTag() async {
    await _authority.printAvailabilityPriceTag();
  }

  Future<void> takePhoto() async {
    await _authority.captureAvailabilityPhoto();
  }

  Future<void> complete() async {
    await _authority.completeAvailability();
  }

  Future<void> resetFill() async {
    await _authority.resetAvailabilityFill();
  }

  @override
  void restorePresentationState(WearScreenId screen, Object state) {}

  @override
  Object? presentationStateFor(WearScreenId screen) => null;

  @override
  Future<void> reset() async {
    await _authority.resetAvailabilityTask();
  }

  void _onState(WearRuntimeState _) {
    if (_disposed) return;
    final WearAvailabilityTaskSlice next = _authority.availabilityTask;
    if (identical(next, _lastTask)) return;
    _lastTask = next;
    final WearAvailabilityRuntimeState mapped = _mapState(next);
    if (!_states.isClosed) _states.add(mapped);
    if (handles(next.screen) && !_updates.isClosed) {
      _updates.add(
        WearBackgroundScreenUpdate(
          screen: next.screen,
          payload: _payload(next),
        ),
      );
    }
  }

  WearAvailabilityRuntimeState _mapState(WearAvailabilityTaskSlice task) {
    return WearAvailabilityRuntimeState(
      flow: task.flow,
      focusedIndex: task.focusedIndex,
      busy: task.isBusy,
      error: task.error,
      savedCount: task.savedCount,
      message: task.message ?? task.flow.message,
    );
  }

  WearGlassesPayload _payload(WearAvailabilityTaskSlice task) {
    if (task.isBusy) {
      return WearAvailabilityGlassesPayloads.loading(
        title: task.screen == WearScreenId.availabilityGroup
            ? 'Товарная группа'
            : 'Доступность',
      );
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
      return WearAvailabilityGlassesPayloads.products(
        group: group,
        products: task.flow.products,
        voiceSnapshot: dynamicVoiceItemsFor(task.screen),
        selectedIndex: task.focusedIndex,
      );
    }
    return WearAvailabilityGlassesPayloads.fromFlow(task.flow);
  }

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

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _authority.resetAvailabilityTask();
    _effectExecutor.deactivate();
    await _subscription.cancel();
    await _states.close();
    await _updates.close();
  }
}
