import 'package:flutter/foundation.dart';

int _nextOperationSequence = 0;

String nextVoskOperationId() {
  _nextOperationSequence++;
  return '${DateTime.now().microsecondsSinceEpoch}-$_nextOperationSequence';
}

Future<T?> invokeDiagnosedVoskMethod<T>({
  required final String operation,
  required final Future<T?> Function(String operationId) invoke,
}) async {
  final operationId = nextVoskOperationId();
  final elapsed = Stopwatch()..start();
  try {
    return await invoke(operationId);
  } finally {
    debugPrint(
      '[VOSK_OPERATION] stage=dart_future_complete '
      'operationId=$operationId operation=$operation '
      'elapsedMs=${elapsed.elapsedMilliseconds}',
    );
  }
}
