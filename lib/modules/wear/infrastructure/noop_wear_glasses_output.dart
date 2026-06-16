import 'package:smart_glasses/modules/wear/application/ports/wear_glasses_output.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

class NoopWearGlassesOutput implements WearGlassesOutput {
  @override
  Future<void> send(WearGlassesPayload payload) async {
    print('[NoopWearGlassesOutput] send screen=${payload.screenType}');
  }
}
