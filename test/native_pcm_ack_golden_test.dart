import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_glasses/core/voice/native_voice_capture.dart';

void main() {
  test('Dart ACK bytes match the Kotlin big-endian protocol golden', () {
    final ByteData acknowledgement = NativePcmPacketEndpoint.acknowledgement(
      NativePcmPacketEndpoint.consumerFailure,
      0x0102030405060708,
      0x1112131415161718,
    );

    expect(
      acknowledgement.buffer.asUint8List(
        acknowledgement.offsetInBytes,
        acknowledgement.lengthInBytes,
      ),
      <int>[
        0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x05,
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
      ],
    );
  });

  test('Dart transport status range stays aligned with Kotlin', () {
    expect(NativePcmPacketEndpoint.accepted, 0);
    expect(NativePcmPacketEndpoint.staleLease, 1);
    expect(NativePcmPacketEndpoint.malformedPacket, 2);
    expect(NativePcmPacketEndpoint.invalidPacket, 3);
    expect(NativePcmPacketEndpoint.consumerRejected, 4);
    expect(NativePcmPacketEndpoint.consumerFailure, 5);
  });
}
