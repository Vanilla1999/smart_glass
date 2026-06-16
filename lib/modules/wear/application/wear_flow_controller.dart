import 'dart:async';
import 'dart:math' as math;

import 'package:smart_glasses/modules/wear/application/ports/wear_glasses_output.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_state.dart';
import 'package:smart_glasses/modules/wear/application/wear_navigation_request.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/application/wear_ui_lifecycle.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_availability_glasses_payloads.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

typedef WearFlowAction = FutureOr<void> Function();

class WearScreenActionHandler {
  const WearScreenActionHandler({
    this.onUp,
    this.onDown,
    this.onSelect,
    this.onBack,
    this.onHome,
  });

  final WearFlowAction? onUp;
  final WearFlowAction? onDown;
  final WearFlowAction? onSelect;
  final WearFlowAction? onBack;
  final WearFlowAction? onHome;
}

class WearFlowController {
  WearFlowController({
    required WearGlassesOutput glassesOutput,
    required WearNavigationOutput navigationOutput,
  })  : _glassesOutput = glassesOutput,
        _navigationOutput = navigationOutput;

  static const int _menuItemCount = 4;
  static const int _availabilityInteractionItemCount = 2;
  static const int _continueScanItemCount = 2;

  WearGlassesOutput _glassesOutput;
  WearNavigationOutput _navigationOutput;
  WearUiLifecycle _uiLifecycle = WearUiLifecycle.inactive;
  WearFlowState _state = WearFlowState.initial();
  final StreamController<WearFlowState> _stateController =
      StreamController<WearFlowState>.broadcast();
  final Map<WearScreenId, WearScreenActionHandler> _screenActions =
      <WearScreenId, WearScreenActionHandler>{};

  WearFlowState get state => _state;

  Stream<WearFlowState> get stateStream => _stateController.stream;

  void setGlassesOutput(WearGlassesOutput output) {
    _glassesOutput = output;
  }

  void setNavigationOutput(WearNavigationOutput output) {
    _navigationOutput = output;
  }

  void setUiLifecycle(WearUiLifecycle lifecycle) {
    _uiLifecycle = lifecycle;
    print('[WearFlowController] uiLifecycle=$lifecycle');
    if (lifecycle == WearUiLifecycle.active) {
      unawaited(flushPendingNavigation());
    }
  }

  void enterScreen(WearScreenId screen, {Object? extra}) {
    _setState(_stateForEnteredScreen(screen, extra: extra));
    unawaited(_renderGlasses());
  }

  void registerScreenActions(
    WearScreenId screen,
    WearScreenActionHandler handler,
  ) {
    _screenActions[screen] = handler;
    print('[WearFlowController] register actions screen=$screen');
  }

  void unregisterScreenActions(WearScreenId screen) {
    _screenActions.remove(screen);
    print('[WearFlowController] unregister actions screen=$screen');
  }

  void setMenuFocusedIndex(int index) {
    final int next = index.clamp(0, _menuItemCount - 1);
    if (_state.menuFocusedIndex == next && _state.screen == WearScreenId.menu) {
      return;
    }
    _setState(
      _state.copyWith(
        screen: WearScreenId.menu,
        focusedIndex: next,
        menuFocusedIndex: next,
        clearError: true,
      ),
    );
    unawaited(_renderGlasses());
  }

  Future<void> selectMenuIndex(int index) async {
    setMenuFocusedIndex(index);
    await _selectFromMenu();
  }

  void setAvailabilityInteractionFocusedIndex(int index) {
    _setAvailabilityInteractionFocus(index);
  }

  Future<void> selectAvailabilityInteractionIndex(int index) async {
    _setAvailabilityInteractionFocus(index);
    await _selectAvailabilityInteraction();
  }

  void setContinueScanFocusedIndex(int index) {
    _setContinueScanFocus(index);
  }

  Future<void> handleVoiceCommand(WearVoiceCommand command) async {
    try {
      print('[WearFlowController] command=$command state=$_state');
      switch (command) {
        case WearVoiceCommand.up:
          await _handleUp();
          break;
        case WearVoiceCommand.down:
          await _handleDown();
          break;
        case WearVoiceCommand.select:
          await _handleSelect();
          break;
        case WearVoiceCommand.back:
          await _handleBack();
          break;
        case WearVoiceCommand.home:
          await _handleHome();
          break;
      }
    } catch (error, stackTrace) {
      print('[WearFlowController] command error=$error\n$stackTrace');
      _setState(_state.copyWith(error: error.toString()));
    }
  }

  Future<void> flushPendingNavigation() async {
    final WearNavigationRequest? request = _state.pendingNavigation;
    if (request == null || _uiLifecycle != WearUiLifecycle.active) return;
    print('[WearFlowController] ui active flush pendingNavigation=$request');
    _setState(_state.copyWith(clearPendingNavigation: true));
    await _navigationOutput.goTo(request.screen, extra: request.extra);
  }

  Future<void> _handleUp() async {
    if (_handleControllerUp()) {
      return;
    }
    if (_state.screen != WearScreenId.menu) {
      if (_uiLifecycle == WearUiLifecycle.active) {
        await _invokeScreenAction(_state.screen, (handler) => handler.onUp);
      }
      return;
    }
    final int next = math.max(0, _state.menuFocusedIndex - 1);
    _setState(_state.copyWith(focusedIndex: next, menuFocusedIndex: next));
    await _renderGlasses();
  }

  Future<void> _handleDown() async {
    if (_handleControllerDown()) {
      return;
    }
    if (_state.screen != WearScreenId.menu) {
      if (_uiLifecycle == WearUiLifecycle.active) {
        await _invokeScreenAction(_state.screen, (handler) => handler.onDown);
      }
      return;
    }
    final int next = math.min(_menuItemCount - 1, _state.menuFocusedIndex + 1);
    _setState(_state.copyWith(focusedIndex: next, menuFocusedIndex: next));
    await _renderGlasses();
  }

  Future<void> _handleSelect() async {
    if (_state.screen == WearScreenId.menu) {
      await _selectFromMenu();
      return;
    }
    if (await _handleControllerSelect()) return;
    if (_uiLifecycle == WearUiLifecycle.inactive) return;
    await _invokeScreenAction(_state.screen, (handler) => handler.onSelect);
  }

  Future<void> _selectFromMenu() async {
    final WearScreenId target = switch (_state.menuFocusedIndex) {
      0 => WearScreenId.printerSelect,
      1 => WearScreenId.availabilityInteraction,
      2 => WearScreenId.help,
      3 => WearScreenId.settings,
      _ => WearScreenId.printerSelect,
    };
    await _navigateTo(target);
  }

  Future<void> _handleBack() async {
    if (_uiLifecycle == WearUiLifecycle.inactive) {
      await _navigateTo(WearScreenId.menu, replaceCurrent: true);
      return;
    }
    final bool handled = await _invokeScreenAction(
      _state.screen,
      (handler) => handler.onBack,
    );
    if (handled) return;
    if (_uiLifecycle == WearUiLifecycle.active) {
      print('[WearFlowController] request navigation back');
      await _navigationOutput.back();
    }
  }

  Future<void> _handleHome() async {
    if (_uiLifecycle == WearUiLifecycle.active) {
      await _invokeScreenAction(_state.screen, (handler) => handler.onHome);
    }
    _setState(_state.copyWith(screen: WearScreenId.menu, clearError: true));
    await _renderGlasses();
    if (_uiLifecycle == WearUiLifecycle.active) {
      print('[WearFlowController] request navigation home');
      await _navigationOutput.home();
      return;
    }
    final WearNavigationRequest request =
        const WearNavigationRequest(screen: WearScreenId.menu);
    print('[WearFlowController] ui inactive pendingNavigation=$request');
    _setState(_state.copyWith(pendingNavigation: request));
  }

  Future<void> _navigateTo(
    WearScreenId target, {
    Object? extra,
    bool replaceCurrent = false,
  }) async {
    final WearNavigationRequest request =
        WearNavigationRequest(screen: target, extra: extra);
    _setState(_stateForEnteredScreen(target, extra: extra));
    await _renderGlasses();
    if (_uiLifecycle == WearUiLifecycle.active) {
      print('[WearFlowController] request navigation target=$request');
      if (replaceCurrent) {
        await _navigationOutput.home();
      } else {
        await _navigationOutput.goTo(target, extra: extra);
      }
      return;
    }
    print('[WearFlowController] ui inactive pendingNavigation=$request');
    _setState(_state.copyWith(pendingNavigation: request));
  }

  WearFlowState _stateForEnteredScreen(WearScreenId screen, {Object? extra}) {
    return switch (screen) {
      WearScreenId.menu => _state.copyWith(
          screen: screen,
          focusedIndex: _state.menuFocusedIndex,
          clearError: true,
        ),
      WearScreenId.availabilityInteraction => _state.copyWith(
          screen: screen,
          focusedIndex: _state.availabilityInteractionFocusedIndex,
          clearError: true,
        ),
      WearScreenId.continueScan => _state.copyWith(
          screen: screen,
          focusedIndex: _state.continueScanFocusedIndex,
          clearError: true,
        ),
      WearScreenId.productSelect => _state.copyWith(
          screen: screen,
          focusedIndex: _state.productFocusedIndex,
          currentProductSelectArgs: extra,
          clearError: true,
        ),
      WearScreenId.availabilityProduct => _state.copyWith(
          screen: screen,
          focusedIndex: _state.availabilityProductFocusedIndex,
          currentAvailabilityGroup: extra,
          clearError: true,
        ),
      WearScreenId.availabilityCheck => _state.copyWith(
          screen: screen,
          currentAvailabilityProduct: extra,
          clearError: true,
        ),
      WearScreenId.status => _state.copyWith(
          screen: screen,
          currentStatusArgs: extra,
          clearError: true,
        ),
      WearScreenId.scanIdle => _state.copyWith(
          screen: screen,
          currentPrinterSelection: extra,
          clearError: true,
        ),
      _ => _state.copyWith(screen: screen, clearError: true),
    };
  }

  bool _handleControllerUp() {
    switch (_state.screen) {
      case WearScreenId.menu:
        return false;
      case WearScreenId.availabilityInteraction:
        _setAvailabilityInteractionFocus(
          math.max(0, _state.availabilityInteractionFocusedIndex - 1),
        );
        return true;
      case WearScreenId.continueScan:
        _setContinueScanFocus(
          math.max(0, _state.continueScanFocusedIndex - 1),
        );
        return true;
      default:
        return false;
    }
  }

  bool _handleControllerDown() {
    switch (_state.screen) {
      case WearScreenId.menu:
        return false;
      case WearScreenId.availabilityInteraction:
        _setAvailabilityInteractionFocus(
          math.min(
            _availabilityInteractionItemCount - 1,
            _state.availabilityInteractionFocusedIndex + 1,
          ),
        );
        return true;
      case WearScreenId.continueScan:
        _setContinueScanFocus(
          math.min(
            _continueScanItemCount - 1,
            _state.continueScanFocusedIndex + 1,
          ),
        );
        return true;
      default:
        return false;
    }
  }

  Future<bool> _handleControllerSelect() async {
    switch (_state.screen) {
      case WearScreenId.availabilityInteraction:
        await _selectAvailabilityInteraction();
        return true;
      case WearScreenId.continueScan:
        if (_uiLifecycle == WearUiLifecycle.active) return false;
        if (_state.continueScanFocusedIndex == 0) {
          await _navigateTo(WearScreenId.scanIdle);
        } else {
          await _navigateTo(WearScreenId.menu, replaceCurrent: true);
        }
        return true;
      case WearScreenId.help:
      case WearScreenId.status:
        await _navigateTo(WearScreenId.menu, replaceCurrent: true);
        return true;
      default:
        return false;
    }
  }

  void _setAvailabilityInteractionFocus(int index) {
    final int next = index.clamp(0, _availabilityInteractionItemCount - 1);
    _setState(
      _state.copyWith(
        focusedIndex: next,
        availabilityInteractionFocusedIndex: next,
        clearError: true,
      ),
    );
    unawaited(_renderGlasses());
  }

  void _setContinueScanFocus(int index) {
    final int next = index.clamp(0, _continueScanItemCount - 1);
    _setState(
      _state.copyWith(
        focusedIndex: next,
        continueScanFocusedIndex: next,
        clearError: true,
      ),
    );
    unawaited(_renderGlasses());
  }

  Future<void> _selectAvailabilityInteraction() async {
    final WearScreenId target = _state.availabilityInteractionFocusedIndex == 0
        ? WearScreenId.availabilityGroup
        : WearScreenId.availabilityDirectScan;
    await _navigateTo(target);
  }

  Future<bool> _invokeScreenAction(
    WearScreenId screen,
    WearFlowAction? Function(WearScreenActionHandler handler) selector,
  ) async {
    final WearScreenActionHandler? handler = _screenActions[screen];
    final WearFlowAction? action =
        selector(handler ?? const WearScreenActionHandler());
    if (action == null) {
      print('[WearFlowController] no screen action screen=$screen');
      return false;
    }
    print('[WearFlowController] invoke screen action screen=$screen');
    await action();
    return true;
  }

  Future<void> _renderGlasses() async {
    final WearGlassesPayload payload = _payloadForState(_state);
    print('[WearFlowController] render glasses screen=${_state.screen}');
    await _glassesOutput.send(payload);
  }

  WearGlassesPayload _payloadForState(WearFlowState state) {
    return switch (state.screen) {
      WearScreenId.menu =>
        WearGlassesPayload.menu(selectedIndex: state.menuFocusedIndex),
      WearScreenId.help => WearGlassesPayload.help(),
      WearScreenId.scanIdle => WearGlassesPayload.scanWaiting(),
      WearScreenId.continueScan => WearGlassesPayload.continueScan(
          selectedIndex: state.continueScanFocusedIndex,
        ),
      WearScreenId.printerSelect => WearGlassesPayload.loading(
          screenType: WearGlassesScreenType.printer,
          title: 'Принтеры',
          statusText: 'Открываем выбор принтера...',
        ),
      WearScreenId.availabilityInteraction =>
        WearAvailabilityGlassesPayloads.interactionTypes(
          selectedIndex: state.availabilityInteractionFocusedIndex,
        ),
      WearScreenId.availabilityGroup ||
      WearScreenId.availabilityProduct ||
      WearScreenId.availabilityDirectScan ||
      WearScreenId.availabilityCheck ||
      WearScreenId.availabilityFill =>
        WearGlassesPayload.loading(
          screenType: WearGlassesScreenType.availability,
          title: 'Доступность',
          statusText: 'Открываем раздел...',
        ),
      WearScreenId.productSelect => WearGlassesPayload.loading(
          screenType: WearGlassesScreenType.productSelect,
          title: 'Выбор товара',
          statusText: 'Открываем список...',
        ),
      WearScreenId.printCodeInput ||
      WearScreenId.status =>
        WearGlassesPayload.status(
          isError: false,
          title: 'Статус',
          statusText: 'Открываем экран...',
        ),
      WearScreenId.settings ||
      WearScreenId.dbSettings =>
        WearGlassesPayload.status(
          isError: false,
          title: 'Настройки',
          statusText: 'Открываем настройки...',
        ),
      WearScreenId.scannerConnect ||
      WearScreenId.main =>
        WearGlassesPayload.authWaitingBarcode(),
    };
  }

  void _setState(WearFlowState next) {
    _state = next;
    print('[WearFlowController] state=$_state');
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  Future<void> dispose() async {
    await _stateController.close();
  }
}
