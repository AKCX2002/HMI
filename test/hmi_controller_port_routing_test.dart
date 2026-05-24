import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hmi_host/core/protocol/hmi_frame.dart';
import 'package:hmi_host/core/serial/serial_transport.dart';
import 'package:hmi_host/features/hmi/hmi_controller.dart';
import 'package:hmi_host/features/hmi/hmi_port_config.dart';
import 'package:hmi_host/features/hmi/hmi_session_frame.dart';

class _FakeSerialTransport implements SerialTransport {
  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast();
  bool _connected = true;
  String? lastPortName;
  int? lastBaudRate;
  int? lastDataBits;
  int? lastStopBits;
  int? lastParity;
  int? lastFlowControl;

  void emit(List<int> bytes) {
    _incoming.add(Uint8List.fromList(bytes));
  }

  @override
  Future<List<String>> availablePorts() async => <String>['FAKE'];

  @override
  Future<void> connect({
    required String portName,
    required int baudRate,
    int dataBits = 8,
    int stopBits = 1,
    int parity = 0,
    int flowControl = 0,
  }) async {
    _connected = true;
    lastPortName = portName;
    lastBaudRate = baudRate;
    lastDataBits = dataBits;
    lastStopBits = stopBits;
    lastParity = parity;
    lastFlowControl = flowControl;
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

List<int> _dgusLogFrame(String text) {
  final bytes = text.codeUnits;
  return <int>[0x5A, 0xA5, bytes.length + 3, 0x82, 0x30, 0x00, ...bytes];
}

List<int> _sessionLogFrame(String text) {
  return HmiSessionFrame(
    type: HmiSessionFrameType.log,
    sequence: 1,
    command: HmiSessionCommand.logPush,
    payload: Uint8List.fromList(<int>[3, ...text.codeUnits]),
  ).encode();
}

void main() {
  test('端口 A 连接时将不兼容的数据位收敛为 8-bit，并继续透传其余串口参数', () async {
    final transportA = _FakeSerialTransport();
    final controller = HmiController(transportA);

    controller.setPortA('FAKE');
    controller.setBaudRateA(19200);
    controller.setDataBitsA(HmiDataBits.bits7);
    controller.setStopBitsA(HmiStopBits.two);
    controller.setParityA(HmiParity.even);
    controller.setFlowControlA(HmiFlowControl.rtsCts);

    await controller.connectPortA();

    expect(controller.portAConfig.dataBits, HmiDataBits.bits8);
    expect(transportA.lastPortName, 'FAKE');
    expect(transportA.lastBaudRate, 19200);
    expect(transportA.lastDataBits, 8);
    expect(transportA.lastStopBits, 2);
    expect(transportA.lastParity, 2);
    expect(transportA.lastFlowControl, 1);

    controller.dispose();
    await transportA.dispose();
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

  test('端口 B 只解析 USART1 Session，不消费 20 字节主协议帧', () async {
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

  test('端口 B 会记录 USART1 Session 日志帧', () async {
    final transportA = _FakeSerialTransport();
    final transportB = _FakeSerialTransport();
    final controller = HmiController(transportA, transportB: transportB);

    transportB.emit(_sessionLogFrame('SESSION_OK'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.logs, hasLength(1));
    expect(controller.logs.first.direction, 'LOG');
    expect(controller.logs.first.decoded.summary, 'SESSION_OK');

    controller.dispose();
    await transportA.dispose();
    await transportB.dispose();
  });

  test('端口 B 不再消费 DGUS 日志帧', () async {
    final transportA = _FakeSerialTransport();
    final transportB = _FakeSerialTransport();
    final controller = HmiController(transportA, transportB: transportB);

    transportB.emit(_dgusLogFrame('HI'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.logs, isEmpty);

    controller.dispose();
    await transportA.dispose();
    await transportB.dispose();
  });

  test('端口 B 收到完整栈快照后更新任务统计总览', () async {
    final transportA = _FakeSerialTransport();
    final transportB = _FakeSerialTransport();
    final controller = HmiController(transportA, transportB: transportB);

    final lines = <String>[
      'STACK_SNAPSHOT_BEGIN',
      'STACK_TASK NAME=ProtoTask TOTAL=384 FREE=320',
      'STACK_TASK NAME=StateMachineTask TOTAL=576 FREE=400',
      'STACK_TASK NAME=MotorTask TOTAL=768 FREE=420',
      'STACK_TASK NAME=AdcTask TOTAL=256 FREE=200',
      'STACK_TASK NAME=CommTask TOTAL=640 FREE=300',
      'STACK_TASK NAME=MonitorTask TOTAL=576 FREE=180',
      'STACK_TASK NAME=HeaterTask TOTAL=448 FREE=390',
      'STACK_SNAPSHOT_END',
    ];
    for (final line in lines) {
      transportB.emit(_sessionLogFrame(line));
    }
    await Future<void>.delayed(Duration.zero);

    expect(controller.latestStackSnapshot, isNotNull);
    expect(controller.stackTaskStats, hasLength(7));
    expect(controller.latestStackSnapshot!.summary.totalWords, 3648);
    expect(
      controller.latestStackSnapshot!.summary.riskiestTaskName,
      'MonitorTask',
    );

    controller.dispose();
    await transportA.dispose();
    await transportB.dispose();
  });

  test('控制器只保留有限数量的结构化栈快照，避免长期运行内存增长', () async {
    final transportA = _FakeSerialTransport();
    final transportB = _FakeSerialTransport();
    final controller = HmiController(transportA, transportB: transportB);

    for (var index = 0; index < 260; index++) {
      final monitorFree = 180 + (index % 5);
      final lines = <String>[
        'STACK_SNAPSHOT_BEGIN',
        'STACK_TASK NAME=ProtoTask TOTAL=384 FREE=320',
        'STACK_TASK NAME=StateMachineTask TOTAL=576 FREE=400',
        'STACK_TASK NAME=MotorTask TOTAL=768 FREE=420',
        'STACK_TASK NAME=AdcTask TOTAL=256 FREE=200',
        'STACK_TASK NAME=CommTask TOTAL=640 FREE=300',
        'STACK_TASK NAME=MonitorTask TOTAL=576 FREE=$monitorFree',
        'STACK_TASK NAME=HeaterTask TOTAL=448 FREE=390',
        'STACK_SNAPSHOT_END',
      ];
      for (final line in lines) {
        transportB.emit(_sessionLogFrame(line));
      }
    }
    await Future<void>.delayed(Duration.zero);

    expect(controller.stackSnapshots.length, lessThanOrEqualTo(240));

    controller.dispose();
    await transportA.dispose();
    await transportB.dispose();
  });
}
