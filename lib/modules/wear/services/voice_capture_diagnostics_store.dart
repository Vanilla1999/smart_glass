class VoiceCaptureDiagnosticsStore {
  int? _captureId;
  Map<String, dynamic>? _latest;

  Map<String, dynamic>? get latest => _latest;

  void beginCapture(int captureId) {
    _captureId = captureId;
    _latest = null;
  }

  void clear() {
    _captureId = null;
    _latest = null;
  }

  void accept(Map<String, dynamic> diagnostics) {
    if (diagnostics['captureId'] != _captureId) return;
    _latest = diagnostics;
  }

  bool get isClientSilenced => _latest?['clientSilenced'] == true;

  bool get hasExplicitNonUvcRoute {
    final Map<String, dynamic>? diagnostics = _latest;
    if (diagnostics == null) return false;
    final String name =
        (diagnostics['routedDeviceName'] as String? ?? '').toLowerCase();
    return name.isNotEmpty &&
        !name.contains('uvc') &&
        !name.contains('usb-audio');
  }
}
