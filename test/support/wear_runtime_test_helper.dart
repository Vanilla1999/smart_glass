import 'package:smart_glasses/modules/wear/application/ports/wear_glasses_output.dart';
import 'package:smart_glasses/modules/wear/application/ports/wear_navigation_output.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_controller.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/domain/auth/model/authenticated_user.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';

Future<WearRuntimeAuthority> createActiveWearRuntimeAuthority({
  WearScreenId initialScreen = WearScreenId.scannerConnect,
}) async {
  final WearRuntimeAuthority authority = WearRuntimeAuthority(
    initialScreen: initialScreen,
  );
  await authority.authorize(
    AuthenticatedUser(idUser: 1, idEmployee: 2, name: 'Test User'),
  );
  await authority.setRuntimeActive(true);
  await authority.setPhoneUiActive(true);
  return authority;
}

WearFlowController createWearFlowController({
  required WearRuntimeAuthority authority,
  required WearGlassesOutput glassesOutput,
  required WearNavigationOutput navigationOutput,
}) {
  return WearFlowController(
    authority: authority,
    glassesOutput: glassesOutput,
    navigationOutput: navigationOutput,
  );
}
