import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/presentation/providers/wear_voice_providers.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/menu/wear_menu_screen.dart';

class WearVoiceCommandHandlers {
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onSelect;
  final VoidCallback? onBack;
  final VoidCallback? onHome;

  const WearVoiceCommandHandlers({
    this.onUp,
    this.onDown,
    this.onSelect,
    this.onBack,
    this.onHome,
  });

  bool get hasAny =>
      onUp != null ||
      onDown != null ||
      onSelect != null ||
      onBack != null ||
      onHome != null;
}

class WearVoiceCallbacksNotifier extends Notifier<WearVoiceCommandHandlers> {
  @override
  WearVoiceCommandHandlers build() {
    return const WearVoiceCommandHandlers();
  }

  void setCallbacks({
    VoidCallback? onUp,
    VoidCallback? onDown,
    VoidCallback? onSelect,
    VoidCallback? onBack,
    VoidCallback? onHome,
  }) {
    state = WearVoiceCommandHandlers(
      onUp: onUp,
      onDown: onDown,
      onSelect: onSelect,
      onBack: onBack,
      onHome: onHome,
    );
  }

  void clear() {
    state = const WearVoiceCommandHandlers();
  }
}

final wearVoiceCallbacksProvider =
    NotifierProvider<WearVoiceCallbacksNotifier, WearVoiceCommandHandlers>(
  WearVoiceCallbacksNotifier.new,
);

class WearVoiceCommandOrchestrator extends ConsumerWidget {
  const WearVoiceCommandOrchestrator({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handlers = ref.watch(wearVoiceCallbacksProvider);

    ref.listen<AsyncValue<WearVoiceCommand>>(
      wearVoiceCommandsProvider,
      (AsyncValue<WearVoiceCommand>? prev, AsyncValue<WearVoiceCommand> next) {
        next.whenData((WearVoiceCommand cmd) {
          final t0 = DateTime.now().millisecondsSinceEpoch;
          print('[VoiceCommandOrchestrator] received: $cmd at $t0');

          bool handled = false;

          if (handlers.hasAny) {
            switch (cmd) {
              case WearVoiceCommand.up:
                print('[VoiceCommandOrchestrator] calling onUp');
                handlers.onUp?.call();
                handled = true;
                break;
              case WearVoiceCommand.down:
                print('[VoiceCommandOrchestrator] calling onDown');
                handlers.onDown?.call();
                handled = true;
                break;
              case WearVoiceCommand.select:
                print('[VoiceCommandOrchestrator] calling onSelect');
                handlers.onSelect?.call();
                handled = true;
                break;
              case WearVoiceCommand.back:
              case WearVoiceCommand.home:
                // Global commands - always handle
                break;
            }
          }

          if (!handled) {
            switch (cmd) {
              case WearVoiceCommand.back:
                print('[VoiceCommandOrchestrator] handling global back');
                if (context.canPop()) {
                  print('[VoiceCommandOrchestrator] popping');
                  context.pop();
                } else {
                  print('[VoiceCommandOrchestrator] cannot pop, no back history');
                }
                break;
              case WearVoiceCommand.home:
                print('[VoiceCommandOrchestrator] handling global home');
                context.go(WearMenuScreen.route);
                break;
              default:
                print('[VoiceCommandOrchestrator] no handlers, command not handled');
            }
          }
        });
      },
    );

    return child;
  }
}

class WearVoiceCommandListener extends ConsumerStatefulWidget {
  const WearVoiceCommandListener({
    super.key,
    required this.child,
    this.onUp,
    this.onDown,
    this.onSelect,
    this.onBack,
    this.onHome,
  });

  final Widget child;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onSelect;
  final VoidCallback? onBack;
  final VoidCallback? onHome;

  @override
  ConsumerState<WearVoiceCommandListener> createState() =>
      _WearVoiceCommandListenerState();
}

class _WearVoiceCommandListenerState
    extends ConsumerState<WearVoiceCommandListener> {
  bool _mounted = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_mounted) {
        _registerCallbacks();
      }
    });
  }

  @override
  void didUpdateWidget(WearVoiceCommandListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_mounted) {
      _registerCallbacks();
    }
  }

  @override
  void dispose() {
    _mounted = false;
    try {
      ref.read(wearVoiceCallbacksProvider.notifier).clear();
    } catch (_) {
      // Widget might be detached
    }
    super.dispose();
  }

  void _registerCallbacks() {
    if (!_mounted) return;
    try {
      ref.read(wearVoiceCallbacksProvider.notifier).setCallbacks(
            onUp: widget.onUp,
            onDown: widget.onDown,
            onSelect: widget.onSelect,
            onBack: widget.onBack,
            onHome: widget.onHome,
          );
    } catch (_) {
      // Widget might be detached
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
