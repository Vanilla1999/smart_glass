import 'dart:async';

import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_state.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

/// Aggregate-first compatibility facade for the remaining simple phone screens.
///
/// The aggregate [WearPresentationFocusSlice] is committed before the legacy
/// controller is updated. The inherited `WearFlowState` fields are therefore a
/// read-only compatibility mirror, not the source of a focus transition.
///
/// This facade is intentionally stateless with respect to business data. It can
/// be removed together with the legacy presentation fields in MR-S12.
class WearAggregatePresentationFlowController extends WearFlowController {
  WearAggregatePresentationFlowController({
    required super.glassesOutput,
    required super.navigationOutput,
    required super.authority,
    super.flashlightToggle,
    super.photoCapture,
  }) {
    _authorityStateSub = this.authority.states.listen(_onAuthorityState);
  }

  Future<void> _presentationCommandTail = Future<void>.value();
  late final StreamSubscription<WearRuntimeState> _authorityStateSub;

  @override
  WearFlowState get state => _projectCompatibilityFocus(super.state);

  /// Commits focus through the one semantic mutation boundary.
  ///
  /// Returns false when the session/screen became stale. Navigation callers must
  /// not continue after a rejected focus receipt.
  Future<bool> commitPresentationFocus(
    WearScreenId screen,
    int index, {
    WearInputModality modality = WearInputModality.touch,
  }) async {
    final int? itemCount = _itemCount(screen);
    if (itemCount == null ||
        authority.payload.navigation.logicalScreen != screen) {
      return false;
    }
    final int next = index.clamp(0, itemCount - 1);
    final WearDispatchResult receipt = await authority.dispatchSemanticInput(
      kind: WearSemanticInputKind.presentationFocus,
      modality: modality,
      expectedScreen: screen,
      expectedSessionEpoch: authority.state.sessionEpoch,
      focusIndex: next,
    );
    if (!receipt.accepted ||
        authority.payload.navigation.logicalScreen != screen) {
      return false;
    }

    // The old controller fields are updated only after the aggregate commit.
    // Its compatibility echo carries the same value and is therefore a no-op at
    // the aggregate reducer. Physical removal belongs to MR-S12.
    _mirrorCommittedFocus(screen, _aggregateFocus(screen));
    return true;
  }

  @override
  void enterScreen(WearScreenId screen, {Object? extra}) {
    _prepareCompatibilityEntry(screen);
    super.enterScreen(screen, extra: extra);
  }

  @override
  void observeRoute(
    WearScreenId screen, {
    Object? extra,
    required bool canPop,
  }) {
    _prepareCompatibilityEntry(screen);
    super.observeRoute(screen, extra: extra, canPop: canPop);
  }

  @override
  void setMenuFocusedIndex(int index) {
    unawaited(commitPresentationFocus(WearScreenId.menu, index));
  }

  @override
  Future<void> selectMenuIndex(int index) async {
    final bool accepted = await commitPresentationFocus(
      WearScreenId.menu,
      index,
    );
    if (!accepted) return;
    await requestNavigation(_menuTarget(_aggregateFocus(WearScreenId.menu)));
  }

  @override
  void setHomeConfirmFocusedIndex(int index) {
    unawaited(commitPresentationFocus(WearScreenId.homeConfirm, index));
  }

  @override
  void setContinueScanFocusedIndex(int index) {
    unawaited(commitPresentationFocus(WearScreenId.continueScan, index));
  }

  @override
  void setAvailabilityInteractionFocusedIndex(int index) {
    unawaited(
      commitPresentationFocus(WearScreenId.availabilityInteraction, index),
    );
  }

  @override
  Future<void> selectAvailabilityInteractionIndex(int index) async {
    final bool accepted = await commitPresentationFocus(
      WearScreenId.availabilityInteraction,
      index,
    );
    if (!accepted) return;
    final WearScreenId target =
        _aggregateFocus(WearScreenId.availabilityInteraction) == 0
            ? WearScreenId.availabilityGroup
            : WearScreenId.availabilityDirectScan;
    await requestNavigation(target);
  }

  @override
  Future<void> handleVoiceCommand(WearVoiceCommand command) {
    final WearScreenId expectedScreen =
        authority.payload.navigation.logicalScreen;
    if (!_ownsPresentationFocus(expectedScreen) ||
        !_isAggregatePresentationCommand(expectedScreen, command)) {
      return super.handleVoiceCommand(command);
    }
    return _enqueuePresentationCommand(() async {
      if (authority.payload.navigation.logicalScreen != expectedScreen) return;
      await _handleAggregatePresentationCommand(
        command,
        expectedScreen,
        WearInputModality.voice,
      );
    });
  }

  @override
  Future<void> handleControllerCommand(WearVoiceCommand command) {
    final WearScreenId screen = authority.payload.navigation.logicalScreen;
    if (!_ownsPresentationFocus(screen) ||
        !_isAggregatePresentationCommand(screen, command)) {
      return super.handleControllerCommand(command);
    }
    return _enqueuePresentationCommand(() async {
      final WearScreenId current = authority.payload.navigation.logicalScreen;
      if (!_ownsPresentationFocus(current)) {
        await super.handleControllerCommand(command);
        return;
      }
      await _handleAggregatePresentationCommand(
        command,
        current,
        WearInputModality.button,
      );
    });
  }

  Future<void> _handleAggregatePresentationCommand(
    WearVoiceCommand command,
    WearScreenId screen,
    WearInputModality modality,
  ) async {
    if (!authority.payload.lifecycle.runtimeActive) return;
    final int current = _aggregateFocus(screen);
    switch (command) {
      case WearVoiceCommand.up:
        await commitPresentationFocus(
          screen,
          current - 1,
          modality: modality,
        );
        return;
      case WearVoiceCommand.down:
        await commitPresentationFocus(
          screen,
          current + 1,
          modality: modality,
        );
        return;
      case WearVoiceCommand.select:
        await _selectCommittedFocus(screen, current, modality);
        return;
      case WearVoiceCommand.continueScan:
        if (screen != WearScreenId.continueScan) {
          await _delegateCommand(command, modality);
          return;
        }
        if (await commitPresentationFocus(screen, 0, modality: modality)) {
          await _delegateCommand(command, modality);
        }
        return;
      case WearVoiceCommand.finish:
        if (screen != WearScreenId.continueScan) {
          await _delegateCommand(command, modality);
          return;
        }
        if (await commitPresentationFocus(screen, 1, modality: modality)) {
          await _delegateCommand(command, modality);
        }
        return;
      case WearVoiceCommand.yes:
        if (screen != WearScreenId.homeConfirm) {
          await _delegateCommand(command, modality);
          return;
        }
        if (await commitPresentationFocus(screen, 0, modality: modality)) {
          await _delegateCommand(command, modality);
        }
        return;
      case WearVoiceCommand.no:
      case WearVoiceCommand.cancel:
        if (screen != WearScreenId.homeConfirm) {
          await _delegateCommand(command, modality);
          return;
        }
        if (await commitPresentationFocus(screen, 1, modality: modality)) {
          await _delegateCommand(command, modality);
        }
        return;
      default:
        await _delegateCommand(command, modality);
    }
  }

  Future<void> _selectCommittedFocus(
    WearScreenId screen,
    int focus,
    WearInputModality modality,
  ) async {
    switch (screen) {
      case WearScreenId.menu:
        await requestNavigation(_menuTarget(focus));
        return;
      case WearScreenId.availabilityInteraction:
        await requestNavigation(
          focus == 0
              ? WearScreenId.availabilityGroup
              : WearScreenId.availabilityDirectScan,
        );
        return;
      case WearScreenId.homeConfirm:
        if (focus == 0) {
          await requestNavigation(WearScreenId.menu, replaceCurrent: true);
        } else {
          await _delegateCommand(WearVoiceCommand.no, modality);
        }
        return;
      case WearScreenId.continueScan:
        await _delegateCommand(
          focus == 0
              ? WearVoiceCommand.continueScan
              : WearVoiceCommand.finish,
          modality,
        );
        return;
      default:
        return;
    }
  }

  Future<void> _delegateCommand(
    WearVoiceCommand command,
    WearInputModality modality,
  ) {
    return modality == WearInputModality.button
        ? super.handleControllerCommand(command)
        : super.handleVoiceCommand(command);
  }

  Future<void> _enqueuePresentationCommand(
    Future<void> Function() action,
  ) {
    final Completer<void> completer = Completer<void>();
    _presentationCommandTail = _presentationCommandTail.then<void>((_) async {
      try {
        await action();
        if (!completer.isCompleted) completer.complete();
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    });
    return completer.future;
  }

  void _onAuthorityState(WearRuntimeState runtimeState) {
    final WearAggregatePayload aggregate =
        runtimeState.payloadAs<WearAggregatePayload>();
    final WearScreenId screen = aggregate.navigation.logicalScreen;
    final int? itemCount = _itemCount(screen);
    if (itemCount == null) return;
    final WearPresentationFocusSlice presentation =
        aggregate.presentation as WearPresentationFocusSlice;
    final int index =
        (presentation.focusFor(screen) ?? 0).clamp(0, itemCount - 1);
    _mirrorCommittedFocus(screen, index);
  }

  void _prepareCompatibilityEntry(WearScreenId screen) {
    if (authority.payload.navigation.logicalScreen != screen ||
        !_ownsPresentationFocus(screen)) {
      return;
    }
    _mirrorCommittedFocus(screen, _aggregateFocus(screen));
  }

  void _mirrorCommittedFocus(WearScreenId screen, int index) {
    if (_legacyFocus(screen) == index) return;
    switch (screen) {
      case WearScreenId.menu:
        super.setMenuFocusedIndex(index);
        return;
      case WearScreenId.homeConfirm:
        super.setHomeConfirmFocusedIndex(index);
        return;
      case WearScreenId.continueScan:
        super.setContinueScanFocusedIndex(index);
        return;
      case WearScreenId.availabilityInteraction:
        super.setAvailabilityInteractionFocusedIndex(index);
        return;
      default:
        return;
    }
  }

  int? _legacyFocus(WearScreenId screen) {
    final WearFlowState legacy = super.state;
    return switch (screen) {
      WearScreenId.menu => legacy.menuFocusedIndex,
      WearScreenId.homeConfirm => legacy.homeConfirmFocusedIndex,
      WearScreenId.continueScan => legacy.continueScanFocusedIndex,
      WearScreenId.availabilityInteraction =>
        legacy.availabilityInteractionFocusedIndex,
      _ => null,
    };
  }

  WearFlowState _projectCompatibilityFocus(WearFlowState value) {
    final WearPresentationFocusSlice presentation =
        authority.payload.presentation as WearPresentationFocusSlice;
    final int menu = presentation.focusFor(WearScreenId.menu) ?? 0;
    final int home = presentation.focusFor(WearScreenId.homeConfirm) ?? 0;
    final int continueScan =
        presentation.focusFor(WearScreenId.continueScan) ?? 0;
    final int availability =
        presentation.focusFor(WearScreenId.availabilityInteraction) ?? 0;
    final int focused = switch (value.screen) {
      WearScreenId.menu => menu,
      WearScreenId.homeConfirm => home,
      WearScreenId.continueScan => continueScan,
      WearScreenId.availabilityInteraction => availability,
      _ => value.focusedIndex,
    };
    return value.copyWith(
      focusedIndex: focused,
      menuFocusedIndex: menu,
      homeConfirmFocusedIndex: home,
      continueScanFocusedIndex: continueScan,
      availabilityInteractionFocusedIndex: availability,
    );
  }

  int _aggregateFocus(WearScreenId screen) {
    final WearPresentationFocusSlice presentation =
        authority.payload.presentation as WearPresentationFocusSlice;
    final int value = presentation.focusFor(screen) ?? 0;
    final int? count = _itemCount(screen);
    return count == null ? value : value.clamp(0, count - 1);
  }

  int? _itemCount(WearScreenId screen) {
    return switch (screen) {
      WearScreenId.menu => 4,
      WearScreenId.homeConfirm ||
      WearScreenId.continueScan ||
      WearScreenId.availabilityInteraction =>
        2,
      _ => null,
    };
  }

  bool _ownsPresentationFocus(WearScreenId screen) =>
      _itemCount(screen) != null;

  bool _isAggregatePresentationCommand(
    WearScreenId screen,
    WearVoiceCommand command,
  ) {
    if (command == WearVoiceCommand.up ||
        command == WearVoiceCommand.down ||
        command == WearVoiceCommand.select) {
      return true;
    }
    if (screen == WearScreenId.continueScan) {
      return command == WearVoiceCommand.continueScan ||
          command == WearVoiceCommand.finish;
    }
    if (screen == WearScreenId.homeConfirm) {
      return command == WearVoiceCommand.yes ||
          command == WearVoiceCommand.no ||
          command == WearVoiceCommand.cancel;
    }
    return false;
  }

  WearScreenId _menuTarget(int index) {
    return switch (index) {
      0 => WearScreenId.printerSelect,
      1 => WearScreenId.availabilityInteraction,
      2 => WearScreenId.help,
      3 => WearScreenId.settings,
      _ => WearScreenId.printerSelect,
    };
  }

  @override
  Future<void> dispose() async {
    await _authorityStateSub.cancel();
    await super.dispose();
  }
}
