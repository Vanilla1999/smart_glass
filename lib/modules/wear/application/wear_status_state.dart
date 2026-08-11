import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/presentation/screens/status/wear_status_args.dart';

enum WearStatusCompletionKind { returnTo, goTo, stay }

class WearStatusCompletion {
  const WearStatusCompletion._(this.kind, this.target);

  const WearStatusCompletion.returnTo(WearScreenId target)
      : this._(WearStatusCompletionKind.returnTo, target);

  const WearStatusCompletion.goTo(WearScreenId target)
      : this._(WearStatusCompletionKind.goTo, target);

  const WearStatusCompletion.stay()
      : this._(WearStatusCompletionKind.stay, null);

  final WearStatusCompletionKind kind;
  final WearScreenId? target;
}

class WearStatusState {
  const WearStatusState({
    required this.args,
    required this.deadline,
    required this.completion,
  });

  final WearStatusScreenArgs args;
  final DateTime? deadline;
  final WearStatusCompletion completion;
}
