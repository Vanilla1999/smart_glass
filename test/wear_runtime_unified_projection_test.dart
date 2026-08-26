import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/modules/wear/application/wear_screen_id.dart';
import 'package:smart_glasses/modules/wear/infrastructure/wear_runtime_glasses_sender.dart';
import 'package:smart_glasses/modules/wear/models/wear_printer.dart';
import 'package:smart_glasses/modules/wear/presentation/glasses/wear_glasses_bridge.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_authority.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_presentation_slice.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_projection.dart';
import 'package:smart_glasses/modules/wear/runtime/wear_runtime_store.dart';

void main() {
  test('screen payload and phone focus come from one committed snapshot',
      () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority(
      initialScreen: WearScreenId.menu,
    );
    await authority.dispatchSemanticInput(
      kind: WearSemanticInputKind.presentationFocus,
      modality: WearInputModality.touch,
      expectedScreen: WearScreenId.menu,
      focusIndex: 2,
    );

    final WearPhoneProjection phone =
        WearRuntimeProjection.projectPhone(authority.state);
    final WearGlassesEnvelope glasses =
        WearRuntimeProjection.projectGlasses(authority.state);

    expect(glasses.logicalScreen, WearScreenId.menu);
    expect(glasses.payload.toJson(), containsPair('screenType', 'menu'));
    expect(phone.version, glasses.version);
    expect(phone.focusedIndex, 2);
    expect(phone.focusedIndex, glasses.payload.selectedIndex);
    expect(phone.items, glasses.payload.items);
    expect(phone.statusText, glasses.payload.statusText);
    await authority.dispose();
  });

  test('projection is deterministic and reads do not create revisions',
      () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority(
      initialScreen: WearScreenId.scanIdle,
    );
    final int revision = authority.state.revision;

    final Map<String, dynamic> first =
        WearRuntimeProjection.projectGlasses(authority.state).toJson();
    final Map<String, dynamic> second =
        WearRuntimeProjection.projectGlasses(authority.state).toJson();

    expect(second, first);
    expect(authority.state.revision, revision);
    await authority.dispose();
  });

  test('printer projection advertises valid hints from committed items',
      () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority(
      initialScreen: WearScreenId.printerSelect,
    );
    final WearAggregatePayload aggregate = authority.payload;
    final WearRuntimeFeaturePayload features = authority.features;
    final WearPrinterTaskSlice printer = features.printer.copyWith(
      phase: WearPrinterTaskPhase.ready,
      printers: const <WearPrinter>[
        WearPrinter(id: '1', name: 'Северный принтер'),
        WearPrinter(id: '2', name: 'Южный терминал'),
      ],
    );
    final WearRuntimeState state = authority.state.withPayload(
      aggregate.copyWith(features: features.copyWith(printer: printer)),
    );

    final payload = WearRuntimeProjection.projectGlasses(state).payload;

    expect(payload.voiceHints, hasLength(payload.items.length));
    expect(payload.voiceHints.map((hint) => hint.itemId), <String>['1', '2']);
    for (var index = 0; index < payload.items.length; index++) {
      expect(
          payload.voiceHints[index].isValidFor(payload.items[index]), isTrue);
    }
    await authority.dispose();
  });

  test('recognition feedback is part of the production projection', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority(
      initialScreen: WearScreenId.menu,
    );
    await authority.store.dispatch(WearRecognitionFeedbackChanged(
      sessionEpoch: authority.state.sessionEpoch,
      expectedScreen: WearScreenId.menu,
      processing: true,
      text: 'Распознаю...',
    ));

    expect(
      WearRuntimeProjection.projectGlasses(authority.state).payload.statusText,
      'Распознаю...',
    );
    await authority.dispose();
  });

  test('overlay is versioned in the same envelope and cannot own navigation',
      () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority(
      initialScreen: WearScreenId.help,
    );
    final WearGlassesEnvelope envelope =
        WearRuntimeProjection.projectGlasses(authority.state);
    final Map<String, dynamic> json = envelope.toJson();
    final Map<String, dynamic> overlay =
        Map<String, dynamic>.from(json['overlay'] as Map);

    expect(overlay['sessionEpoch'], envelope.sessionEpoch);
    expect(overlay['stateRevision'], envelope.stateRevision);
    expect(overlay, isNot(contains('logicalScreen')));
    expect(json['logicalScreen'], 'help');
    await authority.dispose();
  });

  test('reconnect sends the latest full snapshot', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority(
      initialScreen: WearScreenId.menu,
    );
    await authority.navigationAdapter().observePhoneRoute(WearScreenId.menu);
    final _RecordingBridge bridge = _RecordingBridge();
    final WearRuntimeGlassesSender sender = WearRuntimeGlassesSender(
      store: authority.store,
      bridge: bridge,
    )..start();
    await authority.requestNavigation(WearScreenId.help);
    await authority.navigationAdapter().observePhoneRoute(WearScreenId.help);

    await sender.reconnect();

    expect(bridge.shown.last.logicalScreen, WearScreenId.help);
    expect(bridge.shown.last.stateRevision, authority.state.revision);
    await sender.dispose();
    await authority.dispose();
  });

  test('start sends the current full snapshot immediately', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority(
      initialScreen: WearScreenId.scanIdle,
    );
    final _RecordingBridge bridge = _RecordingBridge();
    final WearRuntimeGlassesSender sender = WearRuntimeGlassesSender(
      store: authority.store,
      bridge: bridge,
    )..start();

    await Future<void>.delayed(Duration.zero);

    expect(bridge.shown.single.logicalScreen, WearScreenId.scanIdle);
    await sender.dispose();
    await authority.dispose();
  });

  test('glasses follow logical screen while the phone route is stale',
      () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority(
      initialScreen: WearScreenId.menu,
    );
    final _RecordingBridge bridge = _RecordingBridge();
    final WearRuntimeGlassesSender sender = WearRuntimeGlassesSender(
      store: authority.store,
      bridge: bridge,
    )..start();

    await authority.navigationAdapter().observePhoneRoute(WearScreenId.menu);
    await Future<void>.delayed(Duration.zero);
    expect(bridge.envelopes.last.logicalScreen, WearScreenId.menu);

    await authority.requestNavigation(WearScreenId.help);
    await Future<void>.delayed(Duration.zero);
    expect(bridge.envelopes.last.logicalScreen, WearScreenId.help);
    expect(
      authority.payload.navigation.actualPhoneScreen,
      WearScreenId.menu,
    );

    await sender.dispose();
    await authority.dispose();
  });

  test('reconnect never falls back to a previous session envelope', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority(
      initialScreen: WearScreenId.menu,
    );
    final _RecordingBridge bridge = _RecordingBridge();
    final WearRuntimeGlassesSender sender = WearRuntimeGlassesSender(
      store: authority.store,
      bridge: bridge,
    )..start();
    await authority.navigationAdapter().observePhoneRoute(WearScreenId.menu);
    await Future<void>.delayed(Duration.zero);
    final int previousEpoch = authority.state.sessionEpoch;

    await authority.store.dispatch(WearAdvanceSessionEpoch(
      legacy: WearLegacyRuntimeSnapshot(
        logicalScreen: WearScreenId.main,
        sourceRevision: authority.state.legacy.sourceRevision + 1,
      ),
      payload: authority.payload.copyWith(
        navigation: authority.payload.navigation.request(WearScreenId.main),
      ),
    ));
    await sender.reconnect();

    expect(bridge.shown.last.sessionEpoch, authority.state.sessionEpoch);
    expect(bridge.shown.last.sessionEpoch, isNot(previousEpoch));
    expect(bridge.shown.last.logicalScreen, WearScreenId.main);
    await sender.dispose();
    await authority.dispose();
  });

  test('transport failure does not mutate business revision', () async {
    final WearRuntimeAuthority authority = WearRuntimeAuthority(
      initialScreen: WearScreenId.menu,
    );
    final int revision = authority.state.revision;
    final WearRuntimeGlassesSender sender = WearRuntimeGlassesSender(
      store: authority.store,
      bridge: _RecordingBridge(fail: true),
    )..start();

    await sender.reconnect();

    expect(authority.state.revision, revision);
    await sender.dispose();
    await authority.dispose();
  });
}

class _RecordingBridge extends WearGlassesBridge {
  _RecordingBridge({this.fail = false}) : super(isEnabled: () => true);

  final bool fail;
  final List<WearGlassesEnvelope> shown = <WearGlassesEnvelope>[];
  final List<WearGlassesEnvelope> updated = <WearGlassesEnvelope>[];
  List<WearGlassesEnvelope> get envelopes => <WearGlassesEnvelope>[
        ...shown,
        ...updated,
      ];

  @override
  Future<void> showEnvelope(WearGlassesEnvelope envelope) async {
    if (fail) throw StateError('transport failed');
    shown.add(envelope);
  }

  @override
  Future<void> updateEnvelope(WearGlassesEnvelope envelope) async {
    if (fail) throw StateError('transport failed');
    updated.add(envelope);
  }

  @override
  Future<void> hide() async {}
}
