import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/core/voice/native_voice_capture.dart';

void main() {
  test('decodes production packet and returns accepted acknowledgement',
      () async {
    final NativePcmPacketEndpoint endpoint = NativePcmPacketEndpoint();
    NativePcmPacket? received;
    endpoint.beginSession(
      leaseId: 7,
      revision: 11,
      consumer: (NativePcmPacket packet) {
        received = packet;
        return true;
      },
    );
    endpoint.markStreaming();

    final Uint8List pcm = Uint8List.fromList(<int>[1, 2, 3, 4]);
    final ByteData acknowledgement = await endpoint.handle(_packet(
      leaseId: 7,
      sequence: 0,
      elapsedNanos: 10,
      epochMicros: 20,
      pcm: pcm,
      prefixBytes: 9,
    ));
    pcm.fillRange(0, pcm.length, 0);

    expect(received?.leaseId, 7);
    expect(received?.sequence, 0);
    expect(received?.elapsedRealtimeNanos, 10);
    expect(received?.capturedAtEpochMicros, 20);
    expect(received?.bytes, <int>[1, 2, 3, 4]);
    expect(_ack(acknowledgement), (status: 0, leaseId: 7, sequence: 0));
  });

  test('rejects malformed packets without invoking the consumer', () async {
    var calls = 0;
    final NativePcmPacketEndpoint endpoint = NativePcmPacketEndpoint()
      ..beginSession(
        leaseId: 1,
        revision: 1,
        consumer: (_) {
          calls++;
          return true;
        },
      )
      ..markStreaming();

    expect(_ack(await endpoint.handle(null)).status,
        NativePcmPacketEndpoint.malformedPacket);
    expect(
      _ack(await endpoint.handle(_packet(
        leaseId: 1,
        sequence: 0,
        elapsedNanos: 1,
        epochMicros: 1,
        pcm: Uint8List(2),
        version: 3,
      )))
          .status,
      NativePcmPacketEndpoint.malformedPacket,
    );
    expect(calls, 0);
  });

  test('rejects stale lease, sequence faults, and timestamp regression',
      () async {
    final NativePcmPacketEndpoint endpoint = NativePcmPacketEndpoint()
      ..beginSession(leaseId: 2, revision: 1, consumer: (_) => true)
      ..markStreaming();

    expect(
      _ack(await endpoint.handle(_validPacket(leaseId: 1, sequence: 0))).status,
      NativePcmPacketEndpoint.staleLease,
    );
    expect(
      _ack(await endpoint.handle(_validPacket(leaseId: 2, sequence: 1))).status,
      NativePcmPacketEndpoint.invalidPacket,
    );
    expect(
      _ack(await endpoint.handle(_validPacket(leaseId: 2, sequence: 0))).status,
      NativePcmPacketEndpoint.accepted,
    );
    expect(
      _ack(await endpoint.handle(_validPacket(
        leaseId: 2,
        sequence: 0,
        elapsedNanos: 20,
      )))
          .status,
      NativePcmPacketEndpoint.invalidPacket,
    );
    expect(
      _ack(await endpoint.handle(_validPacket(
        leaseId: 2,
        sequence: 1,
        elapsedNanos: 10,
      )))
          .status,
      NativePcmPacketEndpoint.invalidPacket,
    );
  });

  test('rejects packets before streaming and invalid PCM metadata', () async {
    final NativePcmPacketEndpoint endpoint = NativePcmPacketEndpoint()
      ..beginSession(leaseId: 8, revision: 1, consumer: (_) => true);

    expect(
      _ack(await endpoint.handle(_validPacket(leaseId: 8, sequence: 0))).status,
      NativePcmPacketEndpoint.invalidPacket,
    );
    endpoint.markStreaming();

    for (final ByteData packet in <ByteData>[
      _packet(
        leaseId: 8,
        sequence: 0,
        elapsedNanos: 0,
        epochMicros: 1,
        pcm: Uint8List(2),
      ),
      _packet(
        leaseId: 8,
        sequence: 0,
        elapsedNanos: 1,
        epochMicros: 0,
        pcm: Uint8List(2),
      ),
      _packet(
        leaseId: 8,
        sequence: 0,
        elapsedNanos: 1,
        epochMicros: 1,
        pcm: Uint8List(0),
      ),
      _packet(
        leaseId: 8,
        sequence: 0,
        elapsedNanos: 1,
        epochMicros: 1,
        pcm: Uint8List(1),
      ),
    ]) {
      expect(_ack(await endpoint.handle(packet)).status,
          NativePcmPacketEndpoint.invalidPacket);
    }
  });

  test('only one packet may await acknowledgement', () async {
    final Completer<bool> firstAcknowledgement = Completer<bool>();
    var calls = 0;
    final NativePcmPacketEndpoint endpoint = NativePcmPacketEndpoint()
      ..beginSession(
        leaseId: 3,
        revision: 1,
        consumer: (_) {
          calls++;
          return firstAcknowledgement.future;
        },
      )
      ..markStreaming();

    final Future<ByteData> first =
        endpoint.handle(_validPacket(leaseId: 3, sequence: 0));
    await Future<void>.delayed(Duration.zero);
    final ByteData concurrent =
        await endpoint.handle(_validPacket(leaseId: 3, sequence: 1));
    expect(_ack(concurrent).status, NativePcmPacketEndpoint.invalidPacket);
    expect(calls, 1);

    firstAcknowledgement.complete(true);
    expect(_ack(await first).status, NativePcmPacketEndpoint.accepted);
  });

  test('late acknowledgement cannot mutate a restarted capture', () async {
    final Completer<bool> oldAcknowledgement = Completer<bool>();
    final NativePcmPacketEndpoint endpoint = NativePcmPacketEndpoint()
      ..beginSession(
        leaseId: 4,
        revision: 1,
        consumer: (_) => oldAcknowledgement.future,
      )
      ..markStreaming();
    final Future<ByteData> oldPacket =
        endpoint.handle(_validPacket(leaseId: 4, sequence: 0));
    await Future<void>.delayed(Duration.zero);

    endpoint
      ..endSession()
      ..beginSession(leaseId: 4, revision: 2, consumer: (_) => true)
      ..markStreaming();
    oldAcknowledgement.complete(true);

    expect(_ack(await oldPacket).status, NativePcmPacketEndpoint.staleLease);
    expect(
      _ack(await endpoint.handle(_validPacket(leaseId: 4, sequence: 0))).status,
      NativePcmPacketEndpoint.accepted,
    );
  });

  test('consumer rejection and exception return backlog acknowledgement',
      () async {
    final NativePcmPacketEndpoint rejected = NativePcmPacketEndpoint()
      ..beginSession(leaseId: 5, revision: 1, consumer: (_) => false)
      ..markStreaming();
    final NativePcmPacketEndpoint failed = NativePcmPacketEndpoint()
      ..beginSession(
        leaseId: 6,
        revision: 1,
        consumer: (_) => throw StateError('failed'),
      )
      ..markStreaming();

    expect(
      _ack(await rejected.handle(_validPacket(leaseId: 5, sequence: 0))).status,
      NativePcmPacketEndpoint.consumerRejected,
    );
    expect(
      _ack(await failed.handle(_validPacket(leaseId: 6, sequence: 0))).status,
      NativePcmPacketEndpoint.consumerRejected,
    );
  });
}

ByteData _validPacket({
  required int leaseId,
  required int sequence,
  int elapsedNanos = 20,
}) {
  return _packet(
    leaseId: leaseId,
    sequence: sequence,
    elapsedNanos: elapsedNanos,
    epochMicros: 30,
    pcm: Uint8List.fromList(<int>[1, 2]),
  );
}

ByteData _packet({
  required int leaseId,
  required int sequence,
  required int elapsedNanos,
  required int epochMicros,
  required Uint8List pcm,
  int version = 2,
  int prefixBytes = 0,
}) {
  final ByteData bytes = ByteData(prefixBytes + 40 + pcm.lengthInBytes);
  final int header = prefixBytes;
  bytes
    ..setUint32(header, version, Endian.big)
    ..setUint32(header + 4, 40, Endian.big)
    ..setInt64(header + 8, leaseId, Endian.big)
    ..setInt64(header + 16, sequence, Endian.big)
    ..setInt64(header + 24, elapsedNanos, Endian.big)
    ..setInt64(header + 32, epochMicros, Endian.big);
  bytes.buffer
      .asUint8List()
      .setRange(header + 40, header + 40 + pcm.length, pcm);
  return ByteData.sublistView(bytes, prefixBytes);
}

({int status, int leaseId, int sequence}) _ack(ByteData data) => (
      status: data.getUint32(4, Endian.big),
      leaseId: data.getInt64(8, Endian.big),
      sequence: data.getInt64(16, Endian.big),
    );
