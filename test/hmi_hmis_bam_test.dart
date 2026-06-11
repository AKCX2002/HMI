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
      expect(frames.first.data[15], 0);
      expect(
        frames.every((frame) => frame.function == hmisBamFunction),
        isTrue,
      );
      expect(HmisBamFrameBuilder.fragmentCountOf(frames.first), frames.length);
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
    expect(HmisBamFrameBuilder.fragmentIndexOf(ack!), hmisBamFragIndexAck);
    expect(ack.data[6], 3);
    expect(ack.data[7], HmisBamFrameBuilder.fragmentIndexOf(frames.last));
    expect(ack.data[8], HmisBamControlStatus.ok.value);
    expect(ack.data[15], 0);
    expect(HmiFrame.tryDecode(ack.encode()), isNotNull);
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
    expect(
      HmisBamFrameBuilder.fragmentIndexOf(timeoutResult!.controlToSend!),
      hmisBamFragIndexNack,
    );
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
    expect(
      HmisBamFrameBuilder.fragmentIndexOf(timeoutResult!.controlToSend!),
      hmisBamFragIndexNack,
    );
    expect(decoder.isActive, isFalse);
  });

  test('parses ACK control frame with fragment progress fields', () {
    final session = HmiSessionFrame(
      type: HmiSessionFrameType.response,
      sequence: 3,
      command: HmiSessionCommand.deviceInfo,
      payload: Uint8List.fromList(<int>[
        0x00,
        0x02,
        0x00,
        0x1D,
        0x00,
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

    final transactionId = HmisBamFrameBuilder.readTransactionId(frames[0].data);
    final ack = HmisBamFrameBuilder().buildControl(
      address: 0xFA,
      transactionId: transactionId,
      controlIndex: hmisBamFragIndexAck,
      fragmentIndex: 0,
      status: HmisBamControlStatus.ok,
      nextExpectedIndex: 1,
    );
    final result = decoder.acceptFrame(ack);
    expect(result.consumed, isTrue);
    expect(result.receivedControl, isNotNull);
    expect(result.receivedControl?.fragmentIndex, 0);
    expect(result.receivedControl?.nextExpectedIndex, 1);
    expect(decoder.isActive, isTrue);
  });

  test('ACK with mismatched TID is still surfaced to upper layer', () {
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

    // 发送一个 TID 不匹配的 ACK。
    final ack = HmisBamFrameBuilder().buildControl(
      address: 0xFA,
      transactionId: 0x77,
      controlIndex: hmisBamFragIndexAck,
      fragmentIndex: 0,
      status: HmisBamControlStatus.ok,
      nextExpectedIndex: 1,
    );
    final result = decoder.acceptFrame(ack);
    expect(result.consumed, isTrue);
    expect(result.receivedControl?.transactionId, 0x77);
    expect(decoder.isActive, isTrue);
  });

  test('rejects non-zero reserved byte in data and control frames', () {
    final session = HmiSessionFrame(
      type: HmiSessionFrameType.response,
      sequence: 5,
      command: HmiSessionCommand.hello,
      payload: Uint8List.fromList(<int>[0x00, 0x01]),
    ).encode();
    final frames = HmisBamFrameBuilder().encodePayload(
      address: 0xFA,
      payload: session,
    );
    final badData = HmiFrame(
      address: frames.first.address,
      function: frames.first.function,
      data: List<int>.from(frames.first.data)..[15] = 0x01,
    );

    final decoder = HmisBamDecoder();
    final dataResult = decoder.acceptFrame(badData);
    expect(dataResult.controlToSend, isNotNull);
    expect(
      HmisBamFrameBuilder.fragmentIndexOf(dataResult.controlToSend!),
      hmisBamFragIndexNack,
    );

    final ack = HmisBamFrameBuilder().buildControl(
      address: 0xFA,
      transactionId: HmisBamFrameBuilder.readTransactionId(frames.first.data),
      controlIndex: hmisBamFragIndexAck,
      fragmentIndex: 0,
      status: HmisBamControlStatus.ok,
      nextExpectedIndex: 1,
    );
    final badAck = HmiFrame(
      address: ack.address,
      function: ack.function,
      data: List<int>.from(ack.data)..[15] = 0x01,
    );
    final controlResult = decoder.acceptFrame(badAck);
    expect(controlResult.consumed, isTrue);
    expect(controlResult.receivedControl, isNull);
    expect(controlResult.controlToSend, isNull);
  });
}
