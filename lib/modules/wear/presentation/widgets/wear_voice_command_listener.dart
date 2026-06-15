import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';
import 'package:smart_glasses/modules/wear/presentation/providers/wear_voice_providers.dart';

class WearVoiceCommandOrchestrator extends ConsumerWidget {
  const WearVoiceCommandOrchestrator({
    super.key,
    required this.child,
    required this.onBack,
    required this.onHome,
  });

  final Widget child;
  final VoidCallback onBack;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<WearVoiceCommand>>(
      wearVoiceCommandsProvider,
      (AsyncValue<WearVoiceCommand>? prev, AsyncValue<WearVoiceCommand> next) {
        next.whenData((WearVoiceCommand cmd) {
          final ModalRoute<dynamic>? route = ModalRoute.of(context);
          if (route != null && !route.isCurrent) {
            print(
              '[VoiceCommandOrchestrator] ignoring on non-current route: $cmd',
            );
            return;
          }

          final t0 = DateTime.now().millisecondsSinceEpoch;
          print('[VoiceCommandOrchestrator] received: $cmd at $t0');
          switch (cmd) {
            case WearVoiceCommand.back:
              print('[VoiceCommandOrchestrator] handling global back');
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) return;
                onBack();
              });
              break;
            case WearVoiceCommand.home:
              print('[VoiceCommandOrchestrator] handling global home');
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) return;
                onHome();
              });
              break;
            case WearVoiceCommand.up:
            case WearVoiceCommand.down:
            case WearVoiceCommand.select:
              break;
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
  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<WearVoiceCommand>>(
      wearVoiceCommandsProvider,
      (AsyncValue<WearVoiceCommand>? prev, AsyncValue<WearVoiceCommand> next) {
        next.whenData((WearVoiceCommand cmd) {
          final ModalRoute<dynamic>? route = ModalRoute.of(context);
          if (route != null && !route.isCurrent) {
            print(
              '[WearVoiceCommandListener] ignoring on non-current route: '
              '$cmd route=${route.settings.name}',
            );
            return;
          }

          switch (cmd) {
            case WearVoiceCommand.up:
              if (widget.onUp == null) return;
              print('[WearVoiceCommandListener] calling onUp');
              widget.onUp!.call();
              break;
            case WearVoiceCommand.down:
              if (widget.onDown == null) return;
              print('[WearVoiceCommandListener] calling onDown');
              widget.onDown!.call();
              break;
            case WearVoiceCommand.select:
              if (widget.onSelect == null) return;
              print('[WearVoiceCommandListener] calling onSelect');
              widget.onSelect!.call();
              break;
            case WearVoiceCommand.back:
            case WearVoiceCommand.home:
              break;
          }
        });
      },
    );

    return widget.child;
  }
}
