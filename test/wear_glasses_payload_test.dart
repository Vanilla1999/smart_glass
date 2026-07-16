import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

void main() {
  test('auth waiting payload matches bridge contract', () {
    final Map<String, dynamic> json =
        WearGlassesPayload.authWaitingBarcode().toJson();

    expect(json['screenType'], 'auth');
    expect(json['phase'], 'scanning');
    expect(json['title'], 'Авторизация');
    expect(json['statusText'], 'Поиск ШК...');
    expect(json['isLoading'], isFalse);
    expect(json['isError'], isFalse);
    expect(json['items'], isEmpty);
  });

  test('menu payload contains wear menu items', () {
    final Map<String, dynamic> json = WearGlassesPayload.menu().toJson();

    expect(json['screenType'], 'menu');
    expect(json['phase'], 'idle');
    expect(
      json['items'],
      <String>[
        'Последнее фото',
        'Печать ценников',
        'Доступность',
        'Справка',
        'Настройки',
      ],
    );
    expect(json['selectedIndex'], 0);
  });
}
