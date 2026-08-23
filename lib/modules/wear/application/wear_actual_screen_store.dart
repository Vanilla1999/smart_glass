import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';

/// Read/write compatibility adapter over the authoritative navigation slice.
class WearActualScreenStore {
  WearActualScreenStore(this._authority)
      : _adapter = _authority.navigationAdapter();

  final WearRuntimeAuthority _authority;
  WearRuntimeNavigationAdapter _adapter;

  WearScreenId get screen =>
      _authority.payload.navigation.actualPhoneScreen ??
      _authority.payload.navigation.logicalScreen;
  int get revision =>
      _authority.payload.navigation.routeObservationRevision;

  Future<bool> confirm(WearScreenId screen) async {
    if (_authority.state.terminal ||
        _authority.payload.navigation.actualPhoneScreen == screen) {
      return false;
    }
    if (_adapter.sessionEpoch != _authority.state.sessionEpoch) {
      _adapter = _authority.navigationAdapter();
    }
    final result = await _adapter.observePhoneRoute(screen);
    return result.accepted && result.stateChanged;
  }
}
