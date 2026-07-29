import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:smart_glasses/app/di/dependencies_container.dart';
import 'package:smart_glasses/core/utils/inherited_extension.dart';

/// A scope that provides [DependenciesContainer] to the application
class AppScope extends StatefulWidget {
  const AppScope({
    required this.dependencies,
    required this.child,
    super.key,
  });

  final DependenciesContainer dependencies;
  final Widget child;

  /// Get the dependencies from the [context]
  static DependenciesContainer of(BuildContext context) =>
      context.inhOf<_AppScopeInherited>(listen: false).dependencies;

  @override
  State<AppScope> createState() => _AppScopeState();
}

class _AppScopeState extends State<AppScope> {
  @override
  void dispose() {
    unawaited(widget.dependencies.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AppScopeInherited(
      dependencies: widget.dependencies,
      child: widget.child,
    );
  }
}

/// Private InheritedWidget implementation
class _AppScopeInherited extends InheritedWidget {
  const _AppScopeInherited({
    required super.child,
    required this.dependencies,
  });

  final DependenciesContainer dependencies;

  @override
  bool updateShouldNotify(_AppScopeInherited oldWidget) =>
      !identical(dependencies, oldWidget.dependencies);
}
