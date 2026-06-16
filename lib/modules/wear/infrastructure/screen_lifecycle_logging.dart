import 'package:flutter/widgets.dart';

mixin ScreenLifecycleLogging<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    print('[ScreenLifecycle] ${widget.runtimeType} appeared');
  }

  @override
  void dispose() {
    print('[ScreenLifecycle] ${widget.runtimeType} disappeared');
    super.dispose();
  }
}
