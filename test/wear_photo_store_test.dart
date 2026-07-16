import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_glasses/modules/wear/services/wear_photo_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('stores copied photo path and deletes source URI', () async {
    final Directory directory = await Directory.systemTemp.createTemp();
    addTearDown(() => directory.delete(recursive: true));
    final File photo = File('${directory.path}/latest_photo');
    await photo.writeAsBytes(<int>[1, 2, 3]);
    String? deletedUri;
    final WearPhotoStore store = WearPhotoStore(
      takePhoto: () async => 'content://glasses/photo',
      copyPhotoToAppStorage: (String uri) async {
        expect(uri, 'content://glasses/photo');
        return photo.path;
      },
      deletePhoto: (String uri) async => deletedUri = uri,
    );

    expect(await store.captureLatestPhoto(), photo.path);
    expect((await store.latestPhoto())?.path, photo.path);
    expect(deletedUri, 'content://glasses/photo');
  });

  test('does not delete source URI when local copy fails', () async {
    var deleteCalled = false;
    final WearPhotoStore store = WearPhotoStore(
      takePhoto: () async => 'content://glasses/photo',
      copyPhotoToAppStorage: (_) async => throw Exception('copy failed'),
      deletePhoto: (_) async => deleteCalled = true,
    );

    await expectLater(store.captureLatestPhoto(), throwsException);
    expect(deleteCalled, isFalse);
    expect(await store.latestPhoto(), isNull);
  });
}
