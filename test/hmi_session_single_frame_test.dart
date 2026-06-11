import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hmi_host/core/protocol/hmi_frame.dart';
import 'package:hmi_host/features/hmi/hmi_session_frame.dart';
import 'package:hmi_host/features/hmi/hmi_session_single_frame.dart';

void main() {
  test('encodes short Session payload as FUNC=0x7E fixed 20B frame', () {
    final codec = HmiSessionSingleFrameCodec();
    final session = HmiSessionFrame(
      type: HmiSessionFrameType.request,
      sequence: 0x1234,
      command: HmiSessionCommand.setParamValuesBatch,
      flags: HmiSessionFlags.ackRequired,
      payload: Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
    );

    final frame = codec.encode(address: 0x21, frame: session);
    final raw = frame.encode();
    final decodedOuter = HmiFrame.tryDecode(raw);
    final decodedSession = codec.decode(decodedOuter!);

    expect(raw, hasLength(HmiFrame.frameLength));
    expect(frame.address, 0x21);
    expect(frame.function, hmiSessionSingleFrameFunction);
    expect(frame.data[0], HmiSessionFrameType.request.value);
    expect(frame.data[1], 0x34);
    expect(frame.data[2], 0x12);
    expect(frame.data[3], HmiSessionCommand.setParamValuesBatch.value);
    expect(frame.data[4], HmiSessionFlags.ackRequired);
    expect(frame.data[5], 10);
    expect(frame.data.sublist(6, 16), session.payload);
    expect(decodedSession?.sequence, 0x1234);
    expect(decodedSession?.payload, session.payload);
  });

  test('rejects Session payload longer than single-frame capacity', () {
    final codec = HmiSessionSingleFrameCodec();
    final session = HmiSessionFrame(
      type: HmiSessionFrameType.request,
      sequence: 1,
      command: HmiSessionCommand.getParamValuesBatch,
      payload: Uint8List(11),
    );

    expect(codec.canEncode(session), isFalse);
    expect(
      () => codec.encode(address: 0xFA, frame: session),
      throwsArgumentError,
    );
  });
}
