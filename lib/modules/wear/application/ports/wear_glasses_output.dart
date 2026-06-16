import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

abstract class WearGlassesOutput {
  Future<void> send(WearGlassesPayload payload);
}
