import 'package:flutter/foundation.dart';

typedef VoiceCommandCallback = void Function();

class WearVoiceCommandHandlers {
  VoiceCommandCallback? onUp;
  VoiceCommandCallback? onDown;
  VoiceCommandCallback? onSelect;
  VoiceCommandCallback? onBack;
  VoiceCommandCallback? onHome;

  void clear() {
    onUp = null;
    onDown = null;
    onSelect = null;
    onBack = null;
    onHome = null;
  }

  bool get hasAnyCallbacks =>
      onUp != null ||
      onDown != null ||
      onSelect != null ||
      onBack != null ||
      onHome != null;
}

class WearActiveVoiceHandler {
  WearActiveVoiceHandler._();

  static final WearActiveVoiceHandler I = WearActiveVoiceHandler._();

  WearVoiceCommandHandlers _handlers = WearVoiceCommandHandlers();

  void setHandlers(WearVoiceCommandHandlers handlers) {
    debugPrint('[WearActiveVoiceHandler] setting new handlers');
    _handlers.clear();
    _handlers = handlers;
  }

  void clearHandlers() {
    debugPrint('[WearActiveVoiceHandler] clearing handlers');
    _handlers.clear();
  }

  bool handleCommand(dynamic command) {
    if (!_handlers.hasAnyCallbacks) {
      return false;
    }

    final String cmdName = command.toString();
    debugPrint('[WearActiveVoiceHandler] handling command: $cmdName');

    if (cmdName.contains('up')) {
      _handlers.onUp?.call();
      return true;
    } else if (cmdName.contains('down')) {
      _handlers.onDown?.call();
      return true;
    } else if (cmdName.contains('select')) {
      _handlers.onSelect?.call();
      return true;
    } else if (cmdName.contains('back')) {
      _handlers.onBack?.call();
      return true;
    } else if (cmdName.contains('home')) {
      _handlers.onHome?.call();
      return true;
    }

    return false;
  }
}
