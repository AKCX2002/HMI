import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hmi_host/core/protocol/hmi_frame.dart';
import 'package:hmi_host/core/serial/serial_transport.dart';
import 'package:hmi_host/features/hmi/hmi_controller.dart';

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
  Future<void> connect({required String portName, required int baudRate}) async {
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
  test('端口 A 只解析 20 字节主协议，不消费 DGUS 日志帧', () async {
    final transportA = _FakeSerialTransport();
    final transportB = _FakeSerialTransport();
    final controller = HmiController(transportA, transportB: transportB);

    transportA.emit(<int>[0x5A, 0xA5, 0x07, 0x82, 0x30, 0x00, 0x48, 0x49, 0x00, 0x00]);
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
}
