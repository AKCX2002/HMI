import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hmi_host/features/hmi/hmi_session_frame.dart';

void main() {
  test('encodes and decodes USART1 session frame with Modbus CRC', () {
    final frame = HmiSessionFrame(
      type: HmiSessionFrameType.request,
      sequence: 0x1234,
      command: HmiSessionCommand.hello,
      flags: HmiSessionFlags.ackRequired,
      payload: Uint8List.fromList(<int>[0x01, 0x02]),
    );

    final encoded = frame.encode();

    expect(encoded.sublist(0, 2), <int>[0x55, 0xAA]);
    expect(encoded[2], HmiSessionFrame.protocolVersion);
    expect(encoded[4], 0x34);
    expect(encoded[5], 0x12);
    expect(HmiSessionFrame.tryDecode(encoded), isNotNull);
    expect(HmiSessionFrame.tryDecode(encoded)!.sequence, 0x1234);
    expect(HmiSessionFrame.tryDecode(encoded)!.payload, <int>[0x01, 0x02]);
  });

  test('stream decoder resynchronizes after noise and bad crc', () {
    final good = HmiSessionFrame(
      type: HmiSessionFrameType.log,
      sequence: 7,
      command: HmiSessionCommand.logPush,
      payload: Uint8List.fromList('hello'.codeUnits),
    ).encode();
    final bad = Uint8List.fromList(good);
    bad[bad.length - 1] ^= 0x55;

    final decoder = HmiSessionFrameDecoder();
    final frames = <HmiSessionFrame>[];
    for (final byte in <int>[0x00, 0x13, ...bad, 0x99, ...good]) {
      final frame = decoder.push(byte);
      if (frame != null) {
        frames.add(frame);
      }
    }

    expect(frames, hasLength(1));
    expect(frames.single.command, HmiSessionCommand.logPush);
    expect(String.fromCharCodes(frames.single.payload), 'hello');
  });

  test('stream decoder drains multiple complete frames from one byte batch', () {
    final hello = HmiSessionFrame(
      type: HmiSessionFrameType.response,
      sequence: 1,
      command: HmiSessionCommand.hello,
      payload: Uint8List.fromList(<int>[0x00, 0x01]),
    ).encode();
    final info = HmiSessionFrame(
      type: HmiSessionFrameType.response,
      sequence: 2,
      command: HmiSessionCommand.deviceInfo,
      payload: Uint8List.fromList(<int>[0x00, 0x02, 0x00, 0x1D, 0x00]),
    ).encode();

    final decoder = HmiSessionFrameDecoder();
    final frames = decoder.pushBytes(<int>[...hello, ...info]);

    expect(frames, hasLength(2));
    expect(frames[0].command, HmiSessionCommand.hello);
    expect(frames[1].command, HmiSessionCommand.deviceInfo);
  });

  test('stream decoder skips false 55 AA header with wrong protocol version', () {
    final good = HmiSessionFrame(
      type: HmiSessionFrameType.response,
      sequence: 3,
      command: HmiSessionCommand.hello,
      payload: Uint8List.fromList(<int>[0x00, 0x01]),
    ).encode();

    // 模拟 Android 端混合日志流中的伪头：SOF 正确，但协议版本错误，
    // 同时长度字段看起来合法，旧实现会错误地等待整段伪帧。
    final noise = <int>[
      0x5B,
      0x49,
      0x5D,
      0x20,
      0x55,
      0xAA,
      0x02,
      0x41,
      0x42,
      0x43,
      0x44,
      0x45,
      0x04,
      0x00,
      0x11,
      0x22,
    ];

    final decoder = HmiSessionFrameDecoder();
    final frames = decoder.pushBytes(<int>[...noise, ...good]);

    expect(frames, hasLength(1));
    expect(frames.single.command, HmiSessionCommand.hello);
    expect(frames.single.sequence, 3);
  });
}
