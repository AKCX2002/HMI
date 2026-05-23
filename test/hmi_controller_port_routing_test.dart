import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hmi_host/core/protocol/hmi_frame.dart';
import 'package:hmi_host/core/serial/serial_transport.dart';
import 'package:hmi_host/features/hmi/hmi_controller.dart';
import 'package:hmi_host/features/hmi/hmi_param_config.dart';

class _FakeSerialTransport implements SerialTransport {
  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast();
  bool _connected = true;

  void emit(List<int> bytes) {
    _incoming.add(Uint8List.fromList(bytes));
  }

  @override
  Future<List<String>> availablePorts() async => <String>['FAKE'];

  @override
  Future<void> connect({
    required String portName,
    required int baudRate,
  }) async {
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  @override
  Stream<Uint8List> get incomingBytes => _incoming.stream;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> write(Uint8List bytes) async {}

  Future<void> dispose() async {
    await _incoming.close();
  }
}

void main() {
  test('加热参数映射包含占空比周期与占空比', () async {
    final heaterPeriod = findParamDef(0x50);
    final heaterDuty = findParamDef(0x51);

    expect(heaterPeriod, isNotNull);
    expect(heaterPeriod!.name, '加热占空比周期');
    expect(heaterPeriod.unit, 'ms');
    expect(heaterPeriod.min, 100);
    expect(heaterPeriod.max, 10000);
    expect(heaterPeriod.dgusAddr, 0x2080);

    expect(heaterDuty, isNotNull);
    expect(heaterDuty!.name, '加热占空比');
    expect(heaterDuty.unit, '%');
    expect(heaterDuty.min, 0);
    expect(heaterDuty.max, 100);
    expect(heaterDuty.dgusAddr, 0x2082);
  });

  test('端口 A 只解析 20 字节主协议，不消费 DGUS 日志帧', () async {
    final transportA = _FakeSerialTransport();
    final transportB = _FakeSerialTransport();
    final controller = HmiController(transportA, transportB: transportB);

    transportA.emit(<int>[
      0x5A,
      0xA5,
      0x07,
      0x82,
      0x30,
      0x00,
      0x48,
      0x49,
      0x00,
      0x00,
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.logs, isEmpty);

    controller.dispose();
    await transportA.dispose();
    await transportB.dispose();
  });

  test('端口 B 只解析 DGUS，不消费 20 字节主协议帧', () async {
    final transportA = _FakeSerialTransport();
    final transportB = _FakeSerialTransport();
    final controller = HmiController(transportA, transportB: transportB);

    final frame = HmiFrame(
      address: 0xFA,
      function: 0x40,
      data: const <int>[0x00, 0x00, 0x00],
    ).encode();

    transportB.emit(frame);
    await Future<void>.delayed(Duration.zero);

    expect(controller.logs, isEmpty);

    controller.dispose();
    await transportA.dispose();
    await transportB.dispose();
  });

  test('端口 B 会记录普通 DGUS 读回应', () async {
    final transportA = _FakeSerialTransport();
    final transportB = _FakeSerialTransport();
    final controller = HmiController(transportA, transportB: transportB);

    transportB.emit(<int>[
      0x5A,
      0xA5,
      0x08,
      0x83,
      0x20,
      0x00,
      0x02,
      0x00,
      0x00,
      0x30,
      0x39,
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.logs, hasLength(1));
    expect(
      controller.logs.first.decoded.summary,
      'DGUS RX 5A A5 08 83 20 00 02 00 00 30 39',
    );

    controller.dispose();
    await transportA.dispose();
    await transportB.dispose();
  });

  test('端口 B 会同时记录 DGUS 原始回包和日志文本', () async {
    final transportA = _FakeSerialTransport();
    final transportB = _FakeSerialTransport();
    final controller = HmiController(transportA, transportB: transportB);

    transportB.emit(<int>[
      0x5A,
      0xA5,
      0x07,
      0x82,
      0x30,
      0x00,
      0x48,
      0x49,
      0x00,
      0x00,
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.logs, hasLength(2));
    expect(
      controller.logs[1].decoded.summary,
      'DGUS RX 5A A5 07 82 30 00 48 49 00 00',
    );
    expect(controller.logs[0].decoded.summary, 'HI');

    controller.dispose();
    await transportA.dispose();
    await transportB.dispose();
  });
}
