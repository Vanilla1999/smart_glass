import 'dart:async';
import 'dart:math' as math;

import 'package:multi_scanner/multi_scanner.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_glasses_output.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_state.dart';
import 'package:smart_glasses/modules/wear/application/wear_navigation_request.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/application/wear_ui_lifecycle.dart';
import 'package:smart_glasses/modules/wear/application/voice_clarification_args.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_list_matcher.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/voice_utterance_coordinator.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_availability_glasses_payloads.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_voice_hints.dart';

typedef WearFlowAction = FutureOr<void> Function();
typedef WearFlowPhraseAction = FutureOr<void> Function(String phrase);
typedef WearFlowDynamicItemAction = FutureOr<void> Function(String itemId);
typedef WearFlowPartialPhraseAction = FutureOr<bool> Function(String phrase);
typedef WearDynamicVoiceItems = VoiceDynamicItemsSnapshot Function();
typedef WearFlashlightToggle = Future<void> Function();
typedef WearPhotoCapture = Future<void> Function();

class WearScreenActionHandler {
  const WearScreenActionHandler({
    this.onUp,
    this.onDown,
    this.onSelect,
    this.onYes,
    this.onNo,
    this.onBack,
    this.onHome,
    this.onManualInput,
    this.onPrint,
    this.onPhoto,
    this.onBackToList,
    this.onClear,
    this.onSave,
    this.onCancel,
    this.onConnectScanner,
    this.onSwitchUser,
    this.onOpenDbSettings,
    this.onFillDatabase,
    this.onNextPage,
    this.onPreviousPage,
    this.onContinue,
    this.onFinish,
    this.onPhrase,
    this.onDynamicItem,
    this.onPartialPhrase,
    this.dynamicVoiceItems,
  });

  final WearFlowAction? onUp;
  final WearFlowAction? onDown;
  final WearFlowAction? onSelect;
  final WearFlowAction? onYes;
  final WearFlowAction? onNo;
  final WearFlowAction? onBack;
  final WearFlowAction? onHome;
  final WearFlowAction? onManualInput;
  final WearFlowAction? onPrint;
  final WearFlowAction? onPhoto;
  final WearFlowAction? onBackToList;
  final WearFlowAction? onClear;
  final WearFlowAction? onSave;
  final WearFlowAction? onCancel;
  final WearFlowAction? onConnectScanner;
  final WearFlowAction? onSwitchUser;
  final WearFlowAction? onOpenDbSettings;
  final WearFlowAction? onFillDatabase;
  final WearFlowAction? onNextPage;
  final WearFlowAction? onPreviousPage;
  final WearFlowAction? onContinue;
  final WearFlowAction? onFinish;
  final WearFlowPhraseAction? onPhrase;
  final WearFlowDynamicItemAction? onDynamicItem;
  final WearFlowPartialPhraseAction? onPartialPhrase;
  final WearDynamicVoiceItems? dynamicVoiceItems;
}

class WearFlowController {
  WearFlowController({
    required WearGlassesOutput glassesOutput,
    required WearNavigationOutput navigationOutput,
    WearFlashlightToggle? flashlightToggle,
    WearPhotoCapture? photoCapture,
  })  : _glassesOutput = glassesOutput,
        _navigationOutput = navigationOutput,
        _flashlightToggle = flashlightToggle ?? _toggleScannerFlashlight,
        _photoCapture = photoCapture;

  static const int _menuItemCount = 4;
  static const int _homeConfirmItemCount = 2;
  static const int _availabilityInteractionItemCount = 2;
  static const int _continueScanItemCount = 2;

  WearGlassesOutput _glassesOutput;
  WearNavigationOutput _navigationOutput;
  WearUiLifecycle _uiLifecycle = WearUiLifecycle.inactive;
  WearFlowState _state = WearFlowState.initial();
  final StreamController<WearFlowState> _stateController =
      StreamController<WearFlowState>.broadcast();
  final StreamController<WearScreenId> _screenActionsController =
      StreamController<WearScreenId>.broadcast();
  final Map<WearScreenId, WearScreenActionHandler> _screenActions =
      <WearScreenId, WearScreenActionHandler>{};
  final Map<WearScreenId, WearGlassesPayload> _screenPayloads =
      <WearScreenId, WearGlassesPayload>{};
  final List<WearVoiceCommand> _commandQueue = <WearVoiceCommand>[];
  final WearFlashlightToggle _flashlightToggle;
  final WearPhotoCapture? _photoCapture;
  bool _isProcessingCommand = false;
  bool _isVoiceClarificationSelectionInProgress = false;
  int _nextNavigationRequestId = 0;
  int? _deliveredNavigationRequestId;

  WearFlowState get state => _state;

  Stream<WearFlowState> get stateStream => _stateController.stream;
  Stream<WearScreenId> get screenActionsChanged =>
      _screenActionsController.stream;

  VoiceDynamicItemsSnapshot dynamicVoiceItemsFor(WearScreenId screen) {
    return _screenActions[screen]?.dynamicVoiceItems?.call() ??
        VoiceDynamicItemsSnapshot.empty;
  }

  List<String> voiceGrammarPhrasesFor(WearScreenId screen) {
    if (screen == WearScreenId.voiceClarification &&
        _state.screen == WearScreenId.voiceClarification) {
      return _voiceClarificationPayload(_state)
          .voiceHints
          .map((WearGlassesVoiceHint hint) => hint.phrase.trim())
          .where((String phrase) => phrase.isNotEmpty)
          .toList(growable: false);
    }
    return (_screenPayloads[screen]?.voiceHints ??
            const <WearGlassesVoiceHint>[])
        .map((WearGlassesVoiceHint hint) => hint.phrase.trim())
        .where((String phrase) => phrase.isNotEmpty)
        .toList(growable: false);
  }

  void setGlassesOutput(WearGlassesOutput output) {
    _glassesOutput = output;
  }

  void setNavigationOutput(WearNavigationOutput output) {
    _navigationOutput = output;
  }

  Future<void> renderCurrentGlasses() {
    return _renderGlasses();
  }

  Future<void> setRecognitionDelayVisible(
    WearScreenId screen,
    bool visible,
  ) async {
    if (_state.screen != screen) return;
    final WearGlassesPayload payload =
        _screenPayloads[screen] ?? _payloadForState(_state);
    await _glassesOutput.send(
      visible ? payload.copyWithStatusText('Распознаю...') : payload,
    );
  }

  void setUiLifecycle(WearUiLifecycle lifecycle) {
    _uiLifecycle = lifecycle;
    print('[WearFlowController] uiLifecycle=$lifecycle');
    if (lifecycle == WearUiLifecycle.active) {
      unawaited(flushPendingNavigation());
    }
  }

  void enterScreen(WearScreenId screen, {Object? extra}) {
    _clearContextPayload(screen, extra);
    _setState(_stateForEnteredScreen(screen, extra: extra));
    unawaited(_renderGlasses());
  }

  void registerScreenActions(
    WearScreenId screen,
    WearScreenActionHandler handler,
  ) {
    _screenActions[screen] = handler;
    _screenActionsController.add(screen);
    print('[WearFlowController] register actions screen=$screen');
  }

  void unregisterScreenActions(WearScreenId screen) {
    _screenActions.remove(screen);
    _screenActionsController.add(screen);
    print('[WearFlowController] unregister actions screen=$screen');
  }

  bool canHandleVoiceCommand(WearScreenId screen, WearVoiceCommand command) {
    if (command == WearVoiceCommand.home) {
      return screen != WearScreenId.menu && screen != WearScreenId.homeConfirm;
    }
    final WearScreenActionHandler? handler = _screenActions[screen];
    final bool registered = switch (command) {
      WearVoiceCommand.up => handler?.onUp != null,
      WearVoiceCommand.down => handler?.onDown != null,
      WearVoiceCommand.select => handler?.onSelect != null,
      WearVoiceCommand.yes => handler?.onYes != null,
      WearVoiceCommand.no => handler?.onNo != null,
      WearVoiceCommand.back => handler?.onBack != null,
      WearVoiceCommand.home => handler?.onHome != null,
      WearVoiceCommand.manualInput => handler?.onManualInput != null,
      WearVoiceCommand.print => handler?.onPrint != null,
      WearVoiceCommand.takePhoto => handler?.onPhoto != null,
      WearVoiceCommand.backToList => handler?.onBackToList != null,
      WearVoiceCommand.clear => handler?.onClear != null,
      WearVoiceCommand.save => handler?.onSave != null,
      WearVoiceCommand.cancel => handler?.onCancel != null,
      WearVoiceCommand.connectScanner => handler?.onConnectScanner != null,
      WearVoiceCommand.switchUser => handler?.onSwitchUser != null,
      WearVoiceCommand.openDbSettings => handler?.onOpenDbSettings != null,
      WearVoiceCommand.fillDatabase => handler?.onFillDatabase != null,
      WearVoiceCommand.nextPage => handler?.onNextPage != null,
      WearVoiceCommand.previousPage => handler?.onPreviousPage != null,
      WearVoiceCommand.continueScan => handler?.onContinue != null,
      WearVoiceCommand.finish => handler?.onFinish != null,
      _ => false,
    };
    if (registered) return true;
    return switch (screen) {
      WearScreenId.menu => <WearVoiceCommand>{
          WearVoiceCommand.up,
          WearVoiceCommand.down,
          WearVoiceCommand.select,
          WearVoiceCommand.openPrintPriceTag,
          WearVoiceCommand.openAvailability,
          WearVoiceCommand.openHelp,
          WearVoiceCommand.openSettings,
        }.contains(command),
      WearScreenId.availabilityInteraction => <WearVoiceCommand>{
          WearVoiceCommand.up,
          WearVoiceCommand.down,
          WearVoiceCommand.select,
          WearVoiceCommand.back,
          WearVoiceCommand.home,
          WearVoiceCommand.openList,
          WearVoiceCommand.openDirectScan,
        }.contains(command),
      WearScreenId.homeConfirm ||
      WearScreenId.continueScan =>
        <WearVoiceCommand>{
          WearVoiceCommand.up,
          WearVoiceCommand.down,
          WearVoiceCommand.select,
          WearVoiceCommand.yes,
          WearVoiceCommand.no,
          WearVoiceCommand.back,
        }.contains(command),
      WearScreenId.help ||
      WearScreenId.settings ||
      WearScreenId.printerSelect ||
      WearScreenId.productSelect ||
      WearScreenId.availabilityGroup ||
      WearScreenId.availabilityProduct ||
      WearScreenId.dbSettings ||
      WearScreenId.wifiSettings ||
      WearScreenId.printerSettings ||
      WearScreenId.scanIdle ||
      WearScreenId.availabilityCheck ||
      WearScreenId.availabilityFill =>
        command == WearVoiceCommand.back || command == WearVoiceCommand.home,
      WearScreenId.voiceClarification => <WearVoiceCommand>{
          WearVoiceCommand.back,
          WearVoiceCommand.home,
          WearVoiceCommand.nextPage,
          WearVoiceCommand.previousPage,
        }.contains(command),
      WearScreenId.availabilityDirectScan => <WearVoiceCommand>{
          WearVoiceCommand.back,
          WearVoiceCommand.home,
          WearVoiceCommand.flashlight,
        }.contains(command),
      _ => false,
    };
  }

  void rememberScreenPayload(
    WearScreenId screen,
    WearGlassesPayload payload,
  ) {
    final List<String> previous = voiceGrammarPhrasesFor(screen);
    _screenPayloads[screen] = payload;
    final List<String> next = voiceGrammarPhrasesFor(screen);
    if (!_sameStrings(previous, next)) {
      _screenActionsController.add(screen);
    }
  }

  static bool _sameStrings(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (int index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
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

  void setHomeConfirmFocusedIndex(int index) {
    _setHomeConfirmFocus(index);
  }

  void setAvailabilityInteractionFocusedIndex(int index) {
    _setAvailabilityInteractionFocus(index);
  }

  void setAvailabilityProductFocusedIndex(int index, int itemCount) {
    if (itemCount <= 0) return;
    final int next = index.clamp(0, itemCount - 1);
    _setState(
      _state.copyWith(
        focusedIndex: next,
        availabilityProductFocusedIndex: next,
        clearError: true,
      ),
    );
  }

  Future<void> selectAvailabilityInteractionIndex(int index) async {
    _setAvailabilityInteractionFocus(index);
    await _selectAvailabilityInteraction();
  }

  Future<void> requestNavigation(
    WearScreenId target, {
    Object? extra,
    bool replaceCurrent = false,
  }) async {
    await _navigateTo(target, extra: extra, replaceCurrent: replaceCurrent);
  }

  void setContinueScanFocusedIndex(int index) {
    _setContinueScanFocus(index);
  }

  Future<void> handleVoiceCommand(WearVoiceCommand command) async {
    _commandQueue.add(command);
    if (!_isProcessingCommand) {
      await _drainCommandQueue();
    }
  }

  Future<void> handleVoicePhrase(String phrase) async {
    final String trimmed = phrase.trim();
    if (trimmed.isEmpty || _uiLifecycle == WearUiLifecycle.inactive) return;
    print('[WearFlowController] phrase="$trimmed" state=$_state');
    if (_state.screen != WearScreenId.voiceClarification) {
      final VoiceDynamicItemsSnapshot items =
          dynamicVoiceItemsFor(_state.screen);
      final VoiceListMatch<VoiceDynamicItem> match = VoiceListMatcher.match(
        trimmed,
        items.items,
        (VoiceDynamicItem item) => item.label,
        aliasesOf: (VoiceDynamicItem item) => item.voiceAliases,
      );
      if (match.type == VoiceListMatchType.ambiguous) {
        await _navigateTo(
          WearScreenId.voiceClarification,
          extra: VoiceClarificationArgs(
            sourceScreen: _state.screen,
            phrase: trimmed,
            matches: match.matches,
            sourceListRevision: items.revision,
            spokenPhrases: <String>[trimmed],
            excludedWords: VoiceListMatcher.normalize(trimmed)
                .split(' ')
                .where((String word) => word.isNotEmpty)
                .toSet(),
          ),
        );
        return;
      }
    }
    await _invokeScreenPhrase(_state.screen, trimmed);
  }

  void setVoiceClarificationFocusedIndex(int index, int itemCount) {
    if (itemCount <= 0) return;
    final int next = index.clamp(0, itemCount - 1);
    _setState(
      _state.copyWith(
        focusedIndex: next,
        voiceClarificationFocusedIndex: next,
        clearError: true,
      ),
    );
    unawaited(_renderGlasses());
  }

  void setVoiceClarificationNotice(String? message) {
    if (_state.screen != WearScreenId.voiceClarification) return;
    _setState(
      _state.copyWith(
        voiceClarificationNotice: message,
        clearVoiceClarificationNotice: message == null,
      ),
    );
    unawaited(_renderGlasses());
  }

  Future<bool> selectVoiceClarificationItem(
    VoiceClarificationArgs args,
    String itemId,
  ) async {
    if (_isVoiceClarificationSelectionInProgress ||
        _state.screen != WearScreenId.voiceClarification ||
        !identical(_state.currentVoiceClarificationArgs, args)) {
      return false;
    }
    final WearScreenActionHandler? sourceHandler =
        _screenActions[args.sourceScreen];
    VoiceDynamicItem? selected;
    for (final VoiceDynamicItem item in args.matches) {
      if (item.id == itemId) {
        selected = item;
        break;
      }
    }
    if (selected == null ||
        sourceHandler == null ||
        (sourceHandler.onDynamicItem == null &&
            sourceHandler.onPhrase == null)) {
      return false;
    }
    final VoiceDynamicItem selectedItem = selected;
    final VoiceDynamicItemsSnapshot? currentItems =
        sourceHandler.dynamicVoiceItems?.call();
    if (currentItems == null ||
        currentItems.revision != args.sourceListRevision ||
        !currentItems.items.any((VoiceDynamicItem item) {
          return item.id == selectedItem.id;
        })) {
      return false;
    }

    _isVoiceClarificationSelectionInProgress = true;
    try {
      await _returnToPreviousScreen(args.sourceScreen);
      if (sourceHandler.onDynamicItem != null) {
        await sourceHandler.onDynamicItem!(selectedItem.id);
      } else {
        await sourceHandler.onPhrase!(selectedItem.label);
      }
      return true;
    } finally {
      _isVoiceClarificationSelectionInProgress = false;
    }
  }

  Future<bool> handleVoicePartialPhrase(String phrase) async {
    final String trimmed = phrase.trim();
    if (trimmed.isEmpty || _uiLifecycle == WearUiLifecycle.inactive) {
      return false;
    }
    print('[WearFlowController] partial phrase="$trimmed" state=$_state');
    return _invokeScreenPartialPhrase(_state.screen, trimmed);
  }

  Future<void> _drainCommandQueue() async {
    _isProcessingCommand = true;
    while (_commandQueue.isNotEmpty) {
      final WearVoiceCommand command = _commandQueue.removeAt(0);
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
          case WearVoiceCommand.yes:
            await _handleYes();
            break;
          case WearVoiceCommand.no:
            await _handleNo();
            break;
          case WearVoiceCommand.back:
            await _handleBack();
            break;
          case WearVoiceCommand.home:
            await _handleHome();
            break;
          case WearVoiceCommand.finish:
            await _handleFinish();
            break;
          case WearVoiceCommand.flashlight:
            await _flashlightToggle();
            break;
          case WearVoiceCommand.openPrintPriceTag:
            await _handleOpenPrintPriceTag();
            break;
          case WearVoiceCommand.openAvailability:
            await _handleOpenAvailability();
            break;
          case WearVoiceCommand.openHelp:
            await _handleOpenHelp();
            break;
          case WearVoiceCommand.openSettings:
            await _handleOpenSettings();
            break;
          case WearVoiceCommand.connectScanner:
            await _invokeScreenAction(
              _state.screen,
              (handler) => handler.onConnectScanner,
            );
            break;
          case WearVoiceCommand.switchUser:
            await _invokeScreenAction(
              _state.screen,
              (handler) => handler.onSwitchUser,
            );
            break;
          case WearVoiceCommand.openDbSettings:
            await _invokeScreenAction(
              _state.screen,
              (handler) => handler.onOpenDbSettings,
            );
            break;
          case WearVoiceCommand.fillDatabase:
            await _invokeScreenAction(
              _state.screen,
              (handler) => handler.onFillDatabase,
            );
            break;
          case WearVoiceCommand.continueScan:
            await _handleContinueScan();
            break;
          case WearVoiceCommand.manualInput:
            await _invokeScreenAction(
              _state.screen,
              (handler) => handler.onManualInput,
            );
            break;
          case WearVoiceCommand.print:
            await _handlePrint();
            break;
          case WearVoiceCommand.takePhoto:
            await _invokeScreenAction(
                _state.screen, (handler) => handler.onPhoto);
            break;
          case WearVoiceCommand.testPhoto:
            await _photoCapture?.call();
            break;
          case WearVoiceCommand.backToList:
            await _invokeScreenAction(
              _state.screen,
              (handler) => handler.onBackToList,
            );
            break;
          case WearVoiceCommand.clear:
            await _invokeScreenAction(
                _state.screen, (handler) => handler.onClear);
            break;
          case WearVoiceCommand.save:
            await _invokeScreenAction(
                _state.screen, (handler) => handler.onSave);
            break;
          case WearVoiceCommand.openList:
            await _handleOpenList();
            break;
          case WearVoiceCommand.openDirectScan:
            await _handleOpenDirectScan();
            break;
          case WearVoiceCommand.cancel:
            await _handleCancel();
            break;
          case WearVoiceCommand.nextPage:
            await _invokeScreenAction(
              _state.screen,
              (handler) => handler.onNextPage,
            );
            break;
          case WearVoiceCommand.previousPage:
            await _invokeScreenAction(
              _state.screen,
              (handler) => handler.onPreviousPage,
            );
            break;
          case WearVoiceCommand.stopMicrophone:
          case WearVoiceCommand.startMicrophone:
            break;
        }
      } catch (error, stackTrace) {
        print('[WearFlowController] command error=$error\n$stackTrace');
        _setState(_state.copyWith(error: error.toString()));
      }
    }
    _isProcessingCommand = false;
  }

  Future<void> flushPendingNavigation() async {
    final WearNavigationRequest? request = _state.pendingNavigation;
    if (request == null || _uiLifecycle != WearUiLifecycle.active) return;
    if (_deliveredNavigationRequestId == request.requestId) return;
    print('[WearFlowController] ui active flush pendingNavigation=$request');
    _deliveredNavigationRequestId = request.requestId;
    try {
      if (request.popCurrent) {
        await _navigationOutput.back();
        return;
      }
      if (request.replaceCurrent) {
        await _navigationOutput.home();
        return;
      }
      await _navigationOutput.goTo(request.screen, extra: request.extra);
    } catch (error, stackTrace) {
      if (_state.pendingNavigation?.requestId == request.requestId) {
        _deliveredNavigationRequestId = null;
        _setState(_state.copyWith(error: error.toString()));
      }
      print(
        '[WearFlowController] navigation delivery failed request=$request '
        'error=$error\n$stackTrace',
      );
    }
  }

  bool acknowledgeNavigation({
    required int requestId,
    required WearScreenId screen,
  }) {
    final WearNavigationRequest? request = _state.pendingNavigation;
    if (request == null ||
        request.requestId != requestId ||
        request.screen != screen) {
      return false;
    }
    print('[WearFlowController] navigation acknowledged request=$request');
    _deliveredNavigationRequestId = null;
    _setState(_state.copyWith(clearPendingNavigation: true));
    return true;
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
    unawaited(_renderGlasses());
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
    unawaited(_renderGlasses());
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

  Future<void> _handleYes() async {
    if (_uiLifecycle == WearUiLifecycle.inactive) return;
    final bool handled = await _invokeScreenAction(
      _state.screen,
      (handler) => handler.onYes,
    );
    if (!handled) {
      await _handleSelect();
    }
  }

  Future<void> _handleNo() async {
    if (_uiLifecycle == WearUiLifecycle.inactive) return;
    await _invokeScreenAction(_state.screen, (handler) => handler.onNo);
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
    if (_state.screen == WearScreenId.homeConfirm) {
      return;
    }
    final WearScreenId returnScreen = _state.screen;
    if (_uiLifecycle == WearUiLifecycle.active) {
      await _invokeScreenAction(_state.screen, (handler) => handler.onHome);
    }
    _setState(_state.copyWith(homeConfirmReturnScreen: returnScreen));
    await _navigateTo(WearScreenId.homeConfirm);
  }

  Future<void> _handleFinish() async {
    if (_state.screen == WearScreenId.continueScan) {
      if (_uiLifecycle == WearUiLifecycle.inactive) {
        await _navigateTo(WearScreenId.menu, replaceCurrent: true);
        return;
      }
      await _invokeScreenAction(
        _state.screen,
        (handler) => handler.onFinish,
      );
      return;
    }
    await _invokeScreenAction(_state.screen, (handler) => handler.onFinish);
  }

  Future<void> _handleOpenPrintPriceTag() async {
    if (_state.screen == WearScreenId.menu) {
      await selectMenuIndex(0);
    }
  }

  Future<void> _handlePrint() async {
    if (_state.screen == WearScreenId.menu) {
      await selectMenuIndex(0);
      return;
    }
    await _invokeScreenAction(_state.screen, (handler) => handler.onPrint);
  }

  Future<void> _handleOpenAvailability() async {
    if (_state.screen == WearScreenId.menu) {
      await selectMenuIndex(1);
    }
  }

  Future<void> _handleOpenHelp() async {
    if (_state.screen == WearScreenId.menu) {
      await selectMenuIndex(2);
    }
  }

  Future<void> _handleOpenSettings() async {
    if (_state.screen == WearScreenId.menu) {
      await selectMenuIndex(3);
    }
  }

  Future<void> _handleContinueScan() async {
    if (_state.screen == WearScreenId.continueScan) {
      if (_uiLifecycle == WearUiLifecycle.inactive) {
        _setContinueScanFocus(0);
        await _returnToPreviousScreen(
          WearScreenId.scanIdle,
          extra: _state.currentPrinterSelection,
        );
        return;
      }
      await _invokeScreenAction(
        _state.screen,
        (handler) => handler.onContinue,
      );
    }
  }

  Future<void> _handleOpenList() async {
    if (_state.screen == WearScreenId.availabilityInteraction) {
      await selectAvailabilityInteractionIndex(0);
      return;
    }
    await _invokeScreenAction(_state.screen, (handler) => handler.onBackToList);
  }

  Future<void> _handleOpenDirectScan() async {
    if (_state.screen == WearScreenId.availabilityInteraction) {
      await selectAvailabilityInteractionIndex(1);
    }
  }

  Future<void> _handleCancel() async {
    if (_state.screen == WearScreenId.homeConfirm &&
        _uiLifecycle == WearUiLifecycle.inactive) {
      await _returnToPreviousScreen(_state.homeConfirmReturnScreen);
      return;
    }
    await _invokeScreenAction(_state.screen, (handler) => handler.onCancel);
  }

  static Future<void> _toggleScannerFlashlight() async {
    final MovfastGlassController controller = MovfastGlassController();
    final int currentState = await controller.getFlashlightState();
    await controller.setFlashlight(currentState == 1 ? 0 : 1);
  }

  Future<void> _navigateTo(
    WearScreenId target, {
    Object? extra,
    bool replaceCurrent = false,
  }) async {
    _queueNavigation(
      target,
      extra: extra,
      replaceCurrent: replaceCurrent,
    );
  }

  Future<void> _returnToPreviousScreen(
    WearScreenId target, {
    Object? extra,
  }) async {
    _queueNavigation(target, extra: extra, popCurrent: true);
  }

  void _queueNavigation(
    WearScreenId target, {
    Object? extra,
    bool replaceCurrent = false,
    bool popCurrent = false,
  }) {
    final WearNavigationRequest request = WearNavigationRequest(
      requestId: ++_nextNavigationRequestId,
      screen: target,
      extra: extra,
      replaceCurrent: replaceCurrent,
      popCurrent: popCurrent,
    );
    _clearContextPayload(target, extra);
    _setState(
      _stateForEnteredScreen(target, extra: extra)
          .copyWith(pendingNavigation: request),
    );
    unawaited(_renderGlasses());
    if (_uiLifecycle == WearUiLifecycle.active) {
      print('[WearFlowController] request navigation target=$request');
      unawaited(flushPendingNavigation());
    } else {
      print('[WearFlowController] ui inactive pendingNavigation=$request');
    }
  }

  WearFlowState _stateForEnteredScreen(WearScreenId screen, {Object? extra}) {
    final bool returningFromHomeConfirmToClarification =
        screen == WearScreenId.voiceClarification &&
            _state.screen == WearScreenId.homeConfirm &&
            _state.currentVoiceClarificationArgs != null;
    final WearFlowState next = switch (screen) {
      WearScreenId.menu => _state.copyWith(
          screen: screen,
          focusedIndex: _state.menuFocusedIndex,
          clearError: true,
        ),
      WearScreenId.homeConfirm => _state.copyWith(
          screen: screen,
          focusedIndex: _state.homeConfirmFocusedIndex,
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
      WearScreenId.voiceClarification => _state.copyWith(
          screen: screen,
          focusedIndex: returningFromHomeConfirmToClarification
              ? _state.voiceClarificationFocusedIndex
              : 0,
          voiceClarificationFocusedIndex:
              returningFromHomeConfirmToClarification
                  ? _state.voiceClarificationFocusedIndex
                  : 0,
          currentVoiceClarificationArgs: returningFromHomeConfirmToClarification
              ? _state.currentVoiceClarificationArgs
              : extra,
          clearCurrentVoiceClarificationArgs:
              !returningFromHomeConfirmToClarification && extra == null,
          clearVoiceClarificationNotice: true,
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
    if (screen == WearScreenId.voiceClarification ||
        screen == WearScreenId.homeConfirm) {
      return next.copyWith(clearVoiceClarificationNotice: true);
    }
    return next.copyWith(
      clearCurrentVoiceClarificationArgs: true,
      clearVoiceClarificationNotice: true,
    );
  }

  void _clearContextPayload(WearScreenId screen, Object? extra) {
    switch (screen) {
      case WearScreenId.printerSelect:
        final bool returningFromHomeConfirm =
            _state.screen == WearScreenId.homeConfirm &&
                _state.homeConfirmReturnScreen == WearScreenId.printerSelect;
        if (!returningFromHomeConfirm) {
          _screenPayloads.remove(screen);
        }
        return;
      case WearScreenId.availabilityGroup:
        if (_state.screen != WearScreenId.availabilityProduct) {
          _screenPayloads.remove(screen);
        }
        return;
      case WearScreenId.productSelect:
        if (!identical(extra, _state.currentProductSelectArgs)) {
          _screenPayloads.remove(screen);
        }
        return;
      case WearScreenId.availabilityProduct:
        if (!identical(extra, _state.currentAvailabilityGroup)) {
          _screenPayloads.remove(screen);
        }
        return;
      case WearScreenId.availabilityCheck:
        if (!identical(extra, _state.currentAvailabilityProduct)) {
          _screenPayloads.remove(screen);
        }
        return;
      default:
        return;
    }
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
      case WearScreenId.homeConfirm:
        _setHomeConfirmFocus(
          math.max(0, _state.homeConfirmFocusedIndex - 1),
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
      case WearScreenId.homeConfirm:
        _setHomeConfirmFocus(
          math.min(
              _homeConfirmItemCount - 1, _state.homeConfirmFocusedIndex + 1),
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
      case WearScreenId.homeConfirm:
        await _selectHomeConfirm();
        return true;
      case WearScreenId.continueScan:
        if (_uiLifecycle == WearUiLifecycle.active) return false;
        if (_state.continueScanFocusedIndex == 0) {
          await _returnToPreviousScreen(
            WearScreenId.scanIdle,
            extra: _state.currentPrinterSelection,
          );
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

  void _setHomeConfirmFocus(int index) {
    final int next = index.clamp(0, _homeConfirmItemCount - 1);
    _setState(
      _state.copyWith(
        focusedIndex: next,
        homeConfirmFocusedIndex: next,
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

  Future<void> _selectHomeConfirm() async {
    if (_state.homeConfirmFocusedIndex == 0) {
      await _navigateTo(WearScreenId.menu, replaceCurrent: true);
      return;
    }
    if (_uiLifecycle == WearUiLifecycle.active) {
      await _navigationOutput.back();
      return;
    }
    await _returnToPreviousScreen(_state.homeConfirmReturnScreen);
  }

  Future<bool> _invokeScreenAction(
    WearScreenId screen,
    WearFlowAction? Function(WearScreenActionHandler handler) selector,
  ) async {
    if (_uiLifecycle == WearUiLifecycle.inactive) return false;
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

  Future<bool> _invokeScreenPhrase(WearScreenId screen, String phrase) async {
    final WearScreenActionHandler? handler = _screenActions[screen];
    final WearFlowPhraseAction? action =
        (handler ?? const WearScreenActionHandler()).onPhrase;
    if (action == null) {
      print('[WearFlowController] no phrase action screen=$screen');
      return false;
    }
    print('[WearFlowController] invoke phrase action screen=$screen');
    await action(phrase);
    return true;
  }

  Future<bool> _invokeScreenPartialPhrase(
    WearScreenId screen,
    String phrase,
  ) async {
    final WearScreenActionHandler? handler = _screenActions[screen];
    final WearFlowPartialPhraseAction? action =
        (handler ?? const WearScreenActionHandler()).onPartialPhrase;
    if (action == null) {
      print('[WearFlowController] no partial phrase action screen=$screen');
      return false;
    }
    print('[WearFlowController] invoke partial phrase action screen=$screen');
    return action(phrase);
  }

  Future<void> _renderGlasses() async {
    final WearGlassesPayload payload = _payloadForState(_state);
    print('[WearFlowController] render glasses screen=${_state.screen}');
    try {
      await _glassesOutput.send(payload);
    } catch (error, stackTrace) {
      print(
        '[WearFlowController] glasses projection failed: '
        '$error\n$stackTrace',
      );
    }
  }

  WearGlassesPayload _payloadForState(WearFlowState state) {
    return switch (state.screen) {
      WearScreenId.menu =>
        WearGlassesPayload.menu(selectedIndex: state.menuFocusedIndex),
      WearScreenId.homeConfirm => WearGlassesPayload.homeConfirm(
          selectedIndex: state.homeConfirmFocusedIndex,
        ),
      WearScreenId.help => WearGlassesPayload.help(),
      WearScreenId.scanIdle => WearGlassesPayload.scanWaiting(),
      WearScreenId.continueScan => WearGlassesPayload.continueScan(
          selectedIndex: state.continueScanFocusedIndex,
        ),
      WearScreenId.printerSelect =>
        _screenPayloads[WearScreenId.printerSelect] ??
            WearGlassesPayload.loading(
              screenType: WearGlassesScreenType.printer,
              title: 'Принтеры',
              statusText: 'Открываем выбор принтера...',
            ),
      WearScreenId.availabilityInteraction =>
        WearAvailabilityGlassesPayloads.interactionTypes(
          selectedIndex: state.availabilityInteractionFocusedIndex,
        ),
      WearScreenId.availabilityGroup =>
        _screenPayloads[WearScreenId.availabilityGroup] ??
            WearAvailabilityGlassesPayloads.loading(
              title: 'Товарная группа',
              statusText: 'Загружаем...',
            ),
      WearScreenId.availabilityProduct =>
        _screenPayloads[WearScreenId.availabilityProduct] ??
            WearAvailabilityGlassesPayloads.loading(
              title: 'Товарная позиция',
              statusText: 'Загружаем...',
            ),
      WearScreenId.availabilityDirectScan =>
        _screenPayloads[WearScreenId.availabilityDirectScan] ??
            WearAvailabilityGlassesPayloads.directScanWaiting(),
      WearScreenId.availabilityCheck =>
        _screenPayloads[WearScreenId.availabilityCheck] ??
            WearAvailabilityGlassesPayloads.loading(
              title: 'Проверка товара',
              statusText: 'Загружаем...',
            ),
      WearScreenId.availabilityFill => WearAvailabilityGlassesPayloads.loading(
          title: 'Наполнение базы',
          statusText: 'Загружаем...',
        ),
      WearScreenId.productSelect =>
        _screenPayloads[WearScreenId.productSelect] ??
            WearGlassesPayload.loading(
              screenType: WearGlassesScreenType.productSelect,
              title: 'Выбор товара',
              statusText: 'Открываем список...',
            ),
      WearScreenId.voiceClarification => _voiceClarificationPayload(state),
      WearScreenId.printCodeInput ||
      WearScreenId.status =>
        WearGlassesPayload.status(
          isError: false,
          title: 'Статус',
          statusText: 'Открываем экран...',
        ),
      WearScreenId.settings ||
      WearScreenId.dbSettings ||
      WearScreenId.wifiSettings ||
      WearScreenId.printerSettings =>
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

  WearGlassesPayload _voiceClarificationPayload(WearFlowState state) {
    final VoiceClarificationArgs? args =
        state.currentVoiceClarificationArgs as VoiceClarificationArgs?;
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
        state.voiceClarificationFocusedIndex.clamp(0, matches.length - 1);
    final int pageStart = (selected ~/ pageSize) * pageSize;
    final int page = (selected ~/ pageSize) + 1;
    final int pageCount = ((matches.length - 1) ~/ pageSize) + 1;
    final List<VoiceDynamicItem> visibleMatches =
        matches.skip(pageStart).take(pageSize).toList(growable: false);
    final VoiceDynamicItemsSnapshot snapshot = VoiceDynamicItemsSnapshot(
      revision: Object.hashAll(
        matches.map((VoiceDynamicItem item) => item.revisionHash),
      ),
      items: matches,
    );
    return WearGlassesPayload(
      screenType: WearGlassesScreenType.productSelect,
      phase: WearGlassesPhase.idle,
      title: 'Уточните фразу',
      subtitle: args?.phrase,
      items: visibleMatches
          .map((VoiceDynamicItem item) => item.label)
          .toList(growable: false),
      voiceHints: WearGlassesVoiceHints.forVisibleItems(
        screen: WearScreenId.voiceClarification,
        snapshot: snapshot,
        excludedWords: args?.excludedWords ?? const <String>{},
        visibleItemIds: visibleMatches
            .map((VoiceDynamicItem item) => item.id)
            .toList(growable: false),
      ),
      selectedIndex: selected - pageStart,
      pageText: pageCount > 1 ? 'Страница: $page из $pageCount' : null,
      statusText: state.voiceClarificationNotice,
    );
  }

  void _setState(WearFlowState next) {
    final List<String> previousClarificationGrammar =
        _state.screen == WearScreenId.voiceClarification
            ? voiceGrammarPhrasesFor(WearScreenId.voiceClarification)
            : const <String>[];
    _state = next;
    print('[WearFlowController] state=$_state');
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
    final List<String> nextClarificationGrammar =
        next.screen == WearScreenId.voiceClarification
            ? voiceGrammarPhrasesFor(WearScreenId.voiceClarification)
            : const <String>[];
    if (next.screen == WearScreenId.voiceClarification &&
        !_sameStrings(
          previousClarificationGrammar,
          nextClarificationGrammar,
        )) {
      _screenActionsController.add(WearScreenId.voiceClarification);
    }
  }

  Future<void> dispose() async {
    await _screenActionsController.close();
    await _stateController.close();
  }
}
