import 'package:smart_glasses/modules/wear/application/runtime/wear_runtime_contract.dart';
import 'package:smart_glasses/modules/wear/application/wear_flow_state.dart';

class WearLegacyRuntimeView {
  const WearLegacyRuntimeView({
    required this.flow,
    required this.sourceRevision,
    this.source = 'WearFlowController',
  }) : assert(sourceRevision >= 0);

  final WearFlowState flow;
  final int sourceRevision;
  final String source;

  bool representsSameSourceSnapshot(WearLegacyRuntimeView other) {
    return source == other.source && sourceRevision == other.sourceRevision;
  }
}

final class WearLegacySnapshotObserved extends WearInternalIntent {
  const WearLegacySnapshotObserved(this.snapshot);

  final WearLegacyRuntimeView snapshot;
}

class WearExpectedOperations {
  WearExpectedOperations._(Map<String, WearOperationIdentity> values)
      : _values = Map<String, WearOperationIdentity>.unmodifiable(values);

  factory WearExpectedOperations.empty() {
    return WearExpectedOperations._(<String, WearOperationIdentity>{});
  }

  final Map<String, WearOperationIdentity> _values;

  Map<String, WearOperationIdentity> get values => _values;

  WearOperationIdentity? operator [](String kind) => _values[kind];

  bool expects(WearOperationIdentity identity) {
    return _values[identity.kind] == identity;
  }

  WearExpectedOperations expect(WearOperationIdentity identity) {
    return WearExpectedOperations._(
      <String, WearOperationIdentity>{
        ..._values,
        identity.kind: identity,
      },
    );
  }

  WearExpectedOperations clear(String kind) {
    if (!_values.containsKey(kind)) return this;
    final Map<String, WearOperationIdentity> next =
        Map<String, WearOperationIdentity>.of(_values)..remove(kind);
    return WearExpectedOperations._(next);
  }

  WearExpectedOperations clearAll() {
    if (_values.isEmpty) return this;
    return WearExpectedOperations.empty();
  }
}

class WearRuntimeState {
  const WearRuntimeState({
    required this.version,
    required this.terminal,
    required this.legacy,
    required this.expectedOperations,
  });

  factory WearRuntimeState.initial({WearLegacyRuntimeView? legacy}) {
    return WearRuntimeState(
      version: const WearRuntimeVersion.initial(),
      terminal: false,
      legacy: legacy ??
          WearLegacyRuntimeView(
            flow: WearFlowState.initial(),
            sourceRevision: 0,
          ),
      expectedOperations: WearExpectedOperations.empty(),
    );
  }

  final WearRuntimeVersion version;
  final bool terminal;
  final WearLegacyRuntimeView legacy;
  final WearExpectedOperations expectedOperations;

  int get sessionEpoch => version.sessionEpoch;
  int get revision => version.revision;

  WearRuntimeState copyWith({
    WearRuntimeVersion? version,
    bool? terminal,
    WearLegacyRuntimeView? legacy,
    WearExpectedOperations? expectedOperations,
  }) {
    return WearRuntimeState(
      version: version ?? this.version,
      terminal: terminal ?? this.terminal,
      legacy: legacy ?? this.legacy,
      expectedOperations: expectedOperations ?? this.expectedOperations,
    );
  }

  WearRuntimeState withVersion(WearRuntimeVersion nextVersion) {
    return copyWith(version: nextVersion);
  }
}
