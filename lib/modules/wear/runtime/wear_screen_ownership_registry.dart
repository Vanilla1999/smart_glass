import 'dart:collection';

import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';

/// Immutable ownership map used while feature runtimes are migrated.
///
/// Construction fails immediately when two handlers claim the same logical
/// screen, removing list order as a hidden business rule.
class WearScreenOwnershipRegistry {
  WearScreenOwnershipRegistry(
    Map<String, Iterable<WearScreenId>> claims,
  ) : _owners = _buildOwners(claims);

  final UnmodifiableMapView<WearScreenId, String> _owners;

  String? ownerOf(WearScreenId screen) => _owners[screen];

  bool isOwnedBy(WearScreenId screen, String owner) {
    return _owners[screen] == owner;
  }

  UnmodifiableMapView<WearScreenId, String> get owners => _owners;

  static UnmodifiableMapView<WearScreenId, String> _buildOwners(
    Map<String, Iterable<WearScreenId>> claims,
  ) {
    final Map<WearScreenId, String> owners = <WearScreenId, String>{};
    for (final MapEntry<String, Iterable<WearScreenId>> claim
        in claims.entries) {
      final String owner = claim.key.trim();
      if (owner.isEmpty) {
        throw ArgumentError.value(
            claim.key, 'owner', 'Owner must not be empty');
      }
      for (final WearScreenId screen in claim.value) {
        final String? existing = owners[screen];
        if (existing != null && existing != owner) {
          throw StateError(
            'Wear screen $screen is claimed by both $existing and $owner',
          );
        }
        owners[screen] = owner;
      }
    }
    return UnmodifiableMapView<WearScreenId, String>(owners);
  }
}
