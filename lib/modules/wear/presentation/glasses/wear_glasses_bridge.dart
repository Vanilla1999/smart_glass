import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:smart_glasses/core/services/method_channel_service.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

class WearGlassesBridge {
  WearGlassesBridge({
    MethodChannelService? methodChannelService,
    bool Function()? isEnabled,
  })  : _methodChannelService = methodChannelService ?? MethodChannelService(),
        _isEnabled = isEnabled ?? _defaultIsEnabled;

  final MethodChannelService _methodChannelService;
  final bool Function() _isEnabled;

  Future<void> show(WearGlassesPayload payload) async {
    if (!_isEnabled()) return;
    await _methodChannelService.showWearGlasses(payload.toJson());
  }

  Future<void> update(WearGlassesPayload payload) async {
    if (!_isEnabled()) return;
    await _methodChannelService.updateWearGlasses(payload.toJson());
  }

  Future<void> hide() async {
    if (!_isEnabled()) return;
    await _methodChannelService.hideWearGlasses();
  }

  static bool _defaultIsEnabled() {
    final String? value = dotenv.env['WEAR_GLASSES_ENABLED'];
    return value == null || value == 'true';
  }
}

final WearGlassesBridge wearGlassesBridge = WearGlassesBridge();
