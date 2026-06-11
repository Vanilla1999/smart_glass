class WearAvailabilityGroup {
  const WearAvailabilityGroup({
    required this.id,
    required this.name,
    required this.counter,
  });

  factory WearAvailabilityGroup.fromJson(
    Map<String, dynamic> json, {
    required int counter,
  }) {
    return WearAvailabilityGroup(
      id: _asInt(json['id']),
      name: _asString(json['name']),
      counter: counter,
    );
  }

  final int id;
  final String name;
  final int counter;

  WearAvailabilityGroup copyWith({
    int? counter,
  }) {
    return WearAvailabilityGroup(
      id: id,
      name: name,
      counter: counter ?? this.counter,
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final int? parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw Exception('Некорректный ID группы');
  }

  static String _asString(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    return value.toString();
  }
}
