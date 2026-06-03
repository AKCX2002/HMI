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

  test('timeout resets active transaction', () {
    final session = HmiSessionFrame(
      type: HmiSessionFrameType.response,
      sequence: 1,
      command: HmiSessionCommand.hello,
      payload: Uint8List.fromList(<int>[0x00, 0x01]),
    ).encode();
    final frames = HmisBamFrameBuilder().encodePayload(
      address: 0xFA,
      payload: session,
    );
    expect(frames.length, greaterThanOrEqualTo(2));

    // 只喂入第一个分片，模拟链路中断。
    final now = DateTime.now();
    final decoder = HmisBamDecoder(
      rxTimeout: const Duration(milliseconds: 100),
    );
    decoder.acceptFrame(frames[0]);
    expect(decoder.isActive, isTrue);

    // 立即检查不应超时。
    expect(decoder.checkTimeout(now: now), isNull);

    // 模拟 150ms 后超时。
    final later = now.add(const Duration(milliseconds: 150));
    final timeoutResult = decoder.checkTimeout(now: later);
    expect(timeoutResult, isNotNull);
    expect(timeoutResult?.controlToSend?.data[1], hmisBamFragIndexNack);
    expect(decoder.isActive, isFalse);
  });

  test('pushBytes + checkTimeout for stale transaction', () {
    final session = HmiSessionFrame(
      type: HmiSessionFrameType.log,
      sequence: 2,
      command: HmiSessionCommand.logPush,
      payload: Uint8List.fromList(<int>[3, ...'msg'.codeUnits]),
    ).encode();
    final frames = HmisBamFrameBuilder().encodePayload(
      address: 0xFA,
      payload: session,
    );
    expect(frames.length, 2);

    final decoder = HmisBamDecoder(
      rxTimeout: Duration.zero, // 立即超时
    );
    decoder.acceptFrame(frames[0]);

    // 模拟定时器触发 checkTimeout()。
    final timeoutResult = decoder.checkTimeout();
    expect(timeoutResult, isNotNull);
    expect(timeoutResult?.controlToSend?.data[1], hmisBamFragIndexNack);
    expect(decoder.isActive, isFalse);
  });

  test('ACK with matching session_id resets active transaction', () {
    final session = HmiSessionFrame(
      type: HmiSessionFrameType.response,
      sequence: 3,
      command: HmiSessionCommand.deviceInfo,
      payload: Uint8List.fromList(<int>[
        0x00, 0x02, 0x00, 0x1D, 0x00,
        ...List<int>.filled(24, 0x42),
      ]),
    ).encode();
    final frames = HmisBamFrameBuilder().encodePayload(
      address: 0xFA,
      payload: session,
    );

    final decoder = HmisBamDecoder();
    decoder.acceptFrame(frames[0]);
    expect(decoder.isActive, isTrue);

    final sessionId = frames[0].data[0];
    final ack = HmisBamFrameBuilder().buildControl(
      address: 0xFA,
      sessionId: sessionId,
      controlIndex: hmisBamFragIndexAck,
      status: HmisBamControlStatus.ok,
    );
    final result = decoder.acceptFrame(ack);
    expect(result.consumed, isTrue);
    expect(decoder.isActive, isFalse);
  });

  test('ACK with mismatched session_id does not reset active transaction', () {
    final session = HmiSessionFrame(
      type: HmiSessionFrameType.response,
      sequence: 4,
      command: HmiSessionCommand.hello,
      payload: Uint8List.fromList(<int>[0x00, 0x01]),
    ).encode();
    final frames = HmisBamFrameBuilder().encodePayload(
      address: 0xFA,
      payload: session,
    );

    final decoder = HmisBamDecoder();
    decoder.acceptFrame(frames[0]);
    expect(decoder.isActive, isTrue);

    // 发送一个 session_id 不匹配的 ACK。
    final ack = HmisBamFrameBuilder().buildControl(
      address: 0xFA,
      sessionId: 0x77,
      controlIndex: hmisBamFragIndexAck,
      status: HmisBamControlStatus.ok,
    );
    final result = decoder.acceptFrame(ack);
    expect(result.consumed, isTrue);
    // 事务不受影响，继续等待后续分片。
    expect(decoder.isActive, isTrue);
  });
}
