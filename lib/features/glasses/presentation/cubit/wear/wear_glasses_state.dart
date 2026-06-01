import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_payload.dart';

class WearGlassesState {
  const WearGlassesState({
    required this.screenType,
    required this.phase,
    required this.title,
    this.subtitle,
    this.statusText,
    this.isLoading = false,
    this.isError = false,
    this.items = const <String>[],
    this.selectedIndex = 0,
    this.pageText,
    this.primaryAction,
    this.secondaryAction,
  });

  factory WearGlassesState.initial() {
    return WearGlassesState.fromPayload(
      WearGlassesPayload.authWaitingBarcode().toJson(),
    );
  }

  factory WearGlassesState.fromPayload(Map<String, dynamic> payload) {
    return WearGlassesState(
      screenType: _screenType(payload['screenType']),
      phase: _phase(payload['phase']),
      title: _string(payload['title']) ?? 'Wear',
      subtitle: _string(payload['subtitle']),
      statusText: _string(payload['statusText']),
      isLoading: _bool(payload['isLoading']),
      isError: _bool(payload['isError']),
      items: _items(payload['items']),
      selectedIndex: _int(payload['selectedIndex']),
      pageText: _string(payload['pageText']),
      primaryAction: _string(payload['primaryAction']),
      secondaryAction: _string(payload['secondaryAction']),
    );
  }

  final WearGlassesScreenType screenType;
  final WearGlassesPhase phase;
  final String title;
  final String? subtitle;
  final String? statusText;
  final bool isLoading;
  final bool isError;
  final List<String> items;
  final int selectedIndex;
  final String? pageText;
  final String? primaryAction;
  final String? secondaryAction;

  static WearGlassesScreenType _screenType(dynamic raw) {
    return WearGlassesScreenType.values.firstWhere(
      (WearGlassesScreenType value) => value.name == raw,
      orElse: () => WearGlassesScreenType.status,
    );
  }

  static WearGlassesPhase _phase(dynamic raw) {
    return WearGlassesPhase.values.firstWhere(
      (WearGlassesPhase value) => value.name == raw,
      orElse: () => WearGlassesPhase.idle,
    );
  }

  static List<String> _items(dynamic raw) {
    if (raw is! List) {
      return const <String>[];
    }
    return raw.map((dynamic item) {
      if (item is String) return item;
      if (item is Map && item['title'] != null) return item['title'].toString();
      return item.toString();
    }).toList(growable: false);
  }

  static String? _string(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) return raw;
    return raw.toString();
  }

  static bool _bool(dynamic raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final String? value = _string(raw)?.toLowerCase().trim();
    return value == 'true' || value == '1' || value == 'yes';
  }

  static int _int(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(_string(raw)?.trim() ?? '') ?? 0;
  }
}
