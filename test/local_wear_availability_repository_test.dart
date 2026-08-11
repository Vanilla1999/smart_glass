import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_glasses/modules/wear/data/availability/local_wear_availability_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('completed test product remains available by barcode', () async {
    final LocalWearAvailabilityRepository repository =
        LocalWearAvailabilityRepository();

    await repository.completeProduct(9000000099);

    expect(await repository.findProductsByBarcode('1'), isNotEmpty);
  });

  test('completed regular product remains available by barcode', () async {
    final LocalWearAvailabilityRepository repository =
        LocalWearAvailabilityRepository();

    await repository.completeProduct(3010420008);

    expect(await repository.findProductsByBarcode('4600949140018'), isNotEmpty);
  });
}
