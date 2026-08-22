import 'dart:async';

class WearRuntimeVersion implements Comparable<WearRuntimeVersion> {
  const WearRuntimeVersion({
    required this.sessionEpoch,
    required this.revision,
  })  : assert(sessionEpoch >= 0),
        assert(revision >= 0);

  const WearRuntimeVersion.initial()
      : sessionEpoch = 0,
        revision = 0;

  final int sessionEpoch;
  final int revision;

  WearRuntimeVersion nextRevision() => WearRuntimeVersion(
        sessionEpoch: sessionEpoch,
        revision: revision + 1,
      );

  WearRuntimeVersion nextEpoch() => WearRuntimeVersion(
        sessionEpoch: sessionEpoch + 1,
        revision: 0,
      );

  bool isNewerThan(WearRuntimeVersion other) => compareTo(other) > 0;

  @override
  int compareTo(WearRuntimeVersion other) {
    final int epochOrder = sessionEpoch.compareTo(other.sessionEpoch);
    if (epochOrder != 0) return epochOrder;
    return revision.compareTo(other.revision);
  }

  @override
  bool operator ==(Object other) {
    return other is WearRuntimeVersion &&
        other.sessionEpoch == sessionEpoch &&
        other.revision == revision;
  }

  @override
  int get hashCode => Object.hash(sessionEpoch, revision);

  @override
  String toString() => 'WearRuntimeVersion($sessionEpoch:$revision)';
}

class WearOperationIdentity {
  const WearOperationIdentity({
    required this.sessionEpoch,
    required this.operationId,
    required this.kind,
  })  : assert(sessionEpoch >= 0),
        assert(operationId >= 0);

  final int sessionEpoch;
  final int operationId;
  final String kind;

  bool belongsTo(WearRuntimeVersion version) {
    return sessionEpoch == version.sessionEpoch;
  }

  @override
  bool operator ==(Object other) {
    return other is WearOperationIdentity &&
        other.sessionEpoch == sessionEpoch &&
        other.operationId == operationId &&
        other.kind == kind;
  }

  @override
  int get hashCode => Object.hash(sessionEpoch, operationId, kind);

  @override
  String toString() => '$kind@$sessionEpoch/$operationId';
}

abstract base class WearIntent {
  const WearIntent();

  String get debugLabel => runtimeType.toString();
}

abstract base class WearInternalIntent extends WearIntent {
  const WearInternalIntent();
}

final class WearRuntimeNoOpIntent extends WearInternalIntent {
  const WearRuntimeNoOpIntent();
}

enum WearDispatchStatus {
  accepted,
  noChange,
  rejected,
}

enum WearDispatchRejectReason {
  terminal,
  unsupported,
  invalidState,
  staleScreen,
  staleEpoch,
  staleOperation,
  duplicate,
  busy,
  internalError,
}

class WearDispatchResult {
  const WearDispatchResult._({
    required this.status,
    required this.version,
    required this.scheduledEffectCount,
    this.rejectReason,
    this.message,
  });

  factory WearDispatchResult.accepted({
    required WearRuntimeVersion version,
    required int scheduledEffectCount,
  }) {
    return WearDispatchResult._(
      status: WearDispatchStatus.accepted,
      version: version,
      scheduledEffectCount: scheduledEffectCount,
    );
  }

  factory WearDispatchResult.noChange({
    required WearRuntimeVersion version,
  }) {
    return WearDispatchResult._(
      status: WearDispatchStatus.noChange,
      version: version,
      scheduledEffectCount: 0,
    );
  }

  factory WearDispatchResult.rejected({
    required WearRuntimeVersion version,
    required WearDispatchRejectReason reason,
    String? message,
  }) {
    return WearDispatchResult._(
      status: WearDispatchStatus.rejected,
      version: version,
      scheduledEffectCount: 0,
      rejectReason: reason,
      message: message,
    );
  }

  final WearDispatchStatus status;
  final WearRuntimeVersion version;
  final int scheduledEffectCount;
  final WearDispatchRejectReason? rejectReason;
  final String? message;

  bool get accepted => status != WearDispatchStatus.rejected;
  bool get changed => status == WearDispatchStatus.accepted;
}

abstract base class WearRuntimeEffect {
  const WearRuntimeEffect({
    required this.identity,
    this.exclusiveResource,
  });

  final WearOperationIdentity identity;
  final String? exclusiveResource;

  String get debugLabel => runtimeType.toString();
}

typedef WearEffectResultDispatcher = Future<WearDispatchResult> Function(
  WearIntent intent,
);

typedef WearRuntimeEffectExecutor = Future<WearIntent?> Function(
  WearRuntimeEffect effect,
);

typedef WearRuntimeEffectErrorMapper = WearIntent? Function(
  WearRuntimeEffect effect,
  Object error,
  StackTrace stackTrace,
);

abstract interface class WearRuntimeEffectRunner {
  void schedule(
    WearRuntimeEffect effect,
    WearEffectResultDispatcher dispatchResult,
  );

  Future<void> dispose();
}

final class DetachedWearRuntimeEffectRunner
    implements WearRuntimeEffectRunner {
  DetachedWearRuntimeEffectRunner({
    required WearRuntimeEffectExecutor executor,
    WearRuntimeEffectErrorMapper? errorMapper,
  })  : _executor = executor,
        _errorMapper = errorMapper;

  final WearRuntimeEffectExecutor _executor;
  final WearRuntimeEffectErrorMapper? _errorMapper;
  bool _disposed = false;

  @override
  void schedule(
    WearRuntimeEffect effect,
    WearEffectResultDispatcher dispatchResult,
  ) {
    if (_disposed) return;
    unawaited(
      Future<WearIntent?>.sync(() => _executor(effect)).then<void>(
        (WearIntent? result) {
          if (_disposed || result == null) return;
          unawaited(dispatchResult(result));
        },
        onError: (Object error, StackTrace stackTrace) {
          if (_disposed) return;
          final WearIntent? result =
              _errorMapper?.call(effect, error, stackTrace);
          if (result != null) unawaited(dispatchResult(result));
        },
      ),
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}

final class NoopWearRuntimeEffectRunner implements WearRuntimeEffectRunner {
  bool _disposed = false;

  @override
  void schedule(
    WearRuntimeEffect effect,
    WearEffectResultDispatcher dispatchResult,
  ) {
    if (_disposed) return;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}
