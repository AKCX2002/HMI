import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hmi_host/core/protocol/hmi_frame.dart';
import 'package:hmi_host/features/hmi/hmi_hmis_bam.dart';
import 'package:hmi_host/features/hmi/hmi_session_frame.dart';

void main() {
  test(
    'encodes session payload as 20B HMIS-BAM frames with editable address',
    () {
      final session = HmiSessionFrame(
        type: HmiSessionFrameType.request,
        sequence: 0x1234,
        command: HmiSessionCommand.hello,
        flags: HmiSessionFlags.ackRequired,
        payload: Uint8List.fromList(<int>[0x01, 0x02]),
      ).encode();

      final frames = HmisBamFrameBuilder().encodePayload(
        address: 0x21,
        payload: session,
      );

      expect(frames, isNotEmpty);
      expect(frames.first.address, 0x21);
      expect(
        frames.every((frame) => frame.function == hmisBamFunction),
        isTrue,
      );
      expect(frames.first.data[2], frames.length);
    },
  );

  test('reassembles BAM fragments without assuming a fixed node address', () {
    final session = HmiSessionFrame(
      type: HmiSessionFrameType.response,
      sequence: 7,
      command: HmiSessionCommand.deviceInfo,
      payload: Uint8List.fromList(<int>[
        0x00,
        0x02,
        0x00,
        0x1D,
        0x00,
        ...List<int>.filled(24, 0x41),
      ]),
    ).encode();

    final encoded = HmisBamFrameBuilder()
        .encodePayload(address: 0x37, payload: session)
        .expand((frame) => frame.encode())
        .toList();
    final decoder = HmisBamDecoder();
    final results = decoder.pushBytes(<int>[0x99, 0x88, ...encoded]);
    final completed = results
        .map((result) => result.completed)
        .whereType<HmisBamCompletedFrame>()
        .toList();

    expect(completed, hasLength(1));
    expect(completed.single.address, 0x37);
    expect(HmiSessionFrame.tryDecode(completed.single.payload)?.sequence, 7);
  });

  test('builds ACK control frame after complete reassembly', () {
    final session = HmiSessionFrame(
      type: HmiSessionFrameType.log,
      sequence: 1,
      command: HmiSessionCommand.logPush,
      payload: Uint8List.fromList(<int>[3, ...'ok'.codeUnits]),
    ).encode();

    final frames = HmisBamFrameBuilder().encodePayload(
      address: 0xFA,
      payload: session,
    );
    final decoder = HmisBamDecoder();
    HmisBamDecodeResult? result;
    for (final frame in frames) {
      result = decoder.acceptFrame(frame);
    }
    final completedResult = result;
    expect(completedResult, isNotNull);
    final ack = completedResult!.controlToSend;

    expect(completedResult.completed, isNotNull);
    expect(ack, isNotNull);
    expect(ack?.function, hmisBamFunction);
    expect(ack?.data[1], hmisBamFragIndexAck);
    expect(HmiFrame.tryDecode(ack!.encode()), isNotNull);
  });
}
