import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/domain/service/voice_command/wear_voice_command.dart';

class WearCommandRouter {
  const WearCommandRouter(this._flowController);

  final WearFlowController _flowController;

  Future<void> route(WearVoiceCommand command) {
    return _flowController.handleVoiceCommand(command);
  }
}
