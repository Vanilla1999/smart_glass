/// Scanner state
sealed class ScannerState {
  const ScannerState();
}

/// Scanner is idle
class ScannerIdle extends ScannerState {
  const ScannerIdle();
}

/// Scanner is connecting to service
class ScannerConnecting extends ScannerState {
  const ScannerConnecting();
}

/// Scanner is ready to scan
class ScannerReady extends ScannerState {
  const ScannerReady();
}

/// Barcode scanned successfully
class ScannerScanned extends ScannerState {
  const ScannerScanned(this.barcode);
  
  final String barcode;
}

/// Scanner error occurred
class ScannerError extends ScannerState {
  const ScannerError(this.message);
  
  final String message;
}
