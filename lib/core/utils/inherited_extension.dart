import 'package:flutter/widgets.dart';

/// Extension for accessing InheritedWidget from context
extension InheritedExtension on BuildContext {
  /// Get InheritedWidget of type [T] from context
  /// 
  /// Throws [ArgumentError] if widget not found
  T inhOf<T extends InheritedWidget>({bool listen = true}) =>
      inhMaybeOf<T>(listen: listen) ??
      (throw ArgumentError(
        'Out of scope, not found inherited widget a $T of the exact type',
        'out_of_scope',
      ));

  /// Get InheritedWidget of type [T] from context or null
  T? inhMaybeOf<T extends InheritedWidget>({bool listen = true}) {
    if (listen) {
      return dependOnInheritedWidgetOfExactType<T>();
    } else {
      return getInheritedWidgetOfExactType<T>();
    }
  }
}
