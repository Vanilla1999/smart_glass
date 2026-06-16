import 'package:smart_glasses/modules/wear/application/ports/wear_glasses_output.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';
import 'package:smart_glasses/modules/wear/services/wear_status_icon_reporter.dart';

class FlutterWearGlassesOutput implements WearGlassesOutput {
  @override
  Future<void> send(WearGlassesPayload payload) {
    return WearStatusIconReporter.I.sendFast(payload);
  }
}
