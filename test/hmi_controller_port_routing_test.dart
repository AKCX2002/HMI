import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hmi_host/core/protocol/hmi_frame.dart';
import 'package:hmi_host/core/serial/serial_transport.dart';
import 'package:hmi_host/features/hmi/hmi_controller.dart';
import 'package:hmi_host/features/hmi/hmi_hmis_bam.dart';
import 'package:hmi_host/features/hmi/hmi_port_config.dart';
import 'package:hmi_host/features/hmi/hmi_protocol.dart';
import 'package:hmi_host/features/hmi/hmi_session_frame.dart';

class _FakeSerialTransport implements SerialTransport {
  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast();
  final StreamController<SerialConnectionState> _connectionStates =
      StreamController<SerialConnectionState>.broadcast();
  bool _connected = true;
  Future<void> Function(Uint8List bytes)? onWrite;
  final List<Uint8List> writes = <Uint8List>[];
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
    _connectionStates.add(SerialConnectionState.connected);
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
    _connectionStates.add(SerialConnectionState.disconnected);
  }

  @override
  Stream<Uint8List> get incomingBytes => _incoming.stream;

  @override
  Stream<SerialConnectionState> get connectionStates =>
      _connectionStates.stream;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> write(Uint8List bytes) async {
    writes.add(Uint8List.fromList(bytes));
    await onWrite?.call(bytes);
  }

  Future<void> dispose() async {
    await _connectionStates.close();
    await _incoming.close();
  }
}

List<int> _dgusLogFrame(String text) {
  final bytes = text.codeUnits;
  return <int>[0x5A, 0xA5, bytes.length + 3, 0x82, 0x30, 0x00, ...bytes];
}

class _SessionBamPeer {
  final HmisBamDecoder decoder = HmisBamDecoder();
  final HmisBamFrameBuilder builder = HmisBamFrameBuilder();
  int lastAddress = 0xFA;

  HmiSessionFrame? acceptWrite(Uint8List bytes) {
    for (final result in decoder.pushBytes(bytes)) {
      final completed = result.completed;
      if (completed == null) {
        continue;
      }
      lastAddress = completed.address;
      return HmiSessionFrame.tryDecode(completed.payload);
    }
    return null;
  }

  List<int> wrapSession(List<int> sessionFrame) {
    return builder
        .encodePayload(address: lastAddress, payload: sessionFrame)
        .expand((frame) => frame.encode())
        .toList();
  }
}

List<int> _sessionLogFrame(String text) {
  return _SessionBamPeer().wrapSession(
    HmiSessionFrame(
      type: HmiSessionFrameType.log,
      sequence: 1,
      command: HmiSessionCommand.logPush,
      payload: Uint8List.fromList(<int>[3, ...text.codeUnits]),
    ).encode(),
  );
}

List<int> _sessionResponseFrame({
  required int sequence,
  required HmiSessionCommand command,
  required List<int> payload,
  int address = 0xFA,
}) {
  final peer = _SessionBamPeer()..lastAddress = address;
  return peer.wrapSession(
    HmiSessionFrame(
      type: HmiSessionFrameType.response,
      sequence: sequence,
      command: command,
      payload: Uint8List.fromList(payload),
    ).encode(),
  );
}

List<int> _sessionEventFrame({
  required HmiSessionCommand command,
  required List<int> payload,
  int sequence = 1,
  int address = 0xFA,
}) {
  final peer = _SessionBamPeer()..lastAddress = address;
  return peer.wrapSession(
    HmiSessionFrame(
      type: HmiSessionFrameType.event,
      sequence: sequence,
      command: command,
      payload: Uint8List.fromList(payload),
    ).encode(),
  );
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

  test('快捷控制在仅握手成功时即可发送业务命令', () async {
    final transportA = _FakeSerialTransport();
    final transportB = _FakeSerialTransport();
    final controller = HmiController(transportA, transportB: transportB);
    controller.setSessionNodeAddress(0x21);

    final peer = _SessionBamPeer();
    transportB.onWrite = (bytes) async {
      final frame = peer.acceptWrite(bytes);
      if (frame == null) {
        return;
      }
      if (frame.command == HmiSessionCommand.hello) {
        transportB.emit(
          _sessionResponseFrame(
            sequence: frame.sequence,
            command: HmiSessionCommand.hello,
            payload: <int>[0x00, 0x01],
            address: peer.lastAddress,
          ),
        );
      } else if (frame.command == HmiSessionCommand.controlRunState) {
        transportB.emit(
          _sessionResponseFrame(
            sequence: frame.sequence,
            command: HmiSessionCommand.controlRunState,
            payload: <int>[0x00, 0x01, 0x00],
            address: peer.lastAddress,
          ),
        );
      }
    };

    final ok = await controller.sessionControlRunState(1);

    expect(ok, isTrue);
    expect(controller.sessionHandshakeReady, isTrue);
    expect(controller.sessionQuickControlReady, isTrue);
    expect(transportB.writes.length, greaterThanOrEqualTo(3));
    final decodedWrites = transportB.writes
        .map((bytes) => HmiFrame.tryDecode(bytes))
        .whereType<HmiFrame>()
        .toList();
    expect(decodedWrites, isNotEmpty);
    expect(
      decodedWrites.every((frame) => frame.function == hmisBamFunction),
      isTrue,
    );
    expect(decodedWrites.first.address, 0x21);

    controller.dispose();
    await transportA.dispose();
    await transportB.dispose();
  });

  test('hello 未收到 response 但收到会话事件时仍保持快捷控制可用', () async {
    final transportA = _FakeSerialTransport();
    final transportB = _FakeSerialTransport();
    final controller = HmiController(transportA, transportB: transportB);
    controller.updateRetryPolicy(
      const HmiRetryPolicy(timeoutMs: 20, maxRetries: 1, retryIntervalMs: 0),
    );

    final peer = _SessionBamPeer();
    transportB.onWrite = (bytes) async {
      final frame = peer.acceptWrite(bytes);
      if (frame == null) {
        return;
      }
      if (frame.command == HmiSessionCommand.hello) {
        transportB.emit(
          _sessionEventFrame(
            command: HmiSessionCommand.eventPush,
            payload: <int>[0x01, 0x02, 0x03],
            sequence: 0x4321,
            address: peer.lastAddress,
          ),
        );
      } else if (frame.command == HmiSessionCommand.controlRunState) {
        transportB.emit(
          _sessionResponseFrame(
            sequence: frame.sequence,
            command: HmiSessionCommand.controlRunState,
            payload: <int>[0x00, 0x01, 0x00],
            address: peer.lastAddress,
          ),
        );
      }
    };

    final ok = await controller.sessionControlRunState(1);

    expect(ok, isTrue);
    expect(controller.sessionHandshakeReady, isTrue);
    expect(controller.sessionQuickControlReady, isTrue);
    expect(transportB.writes.length, greaterThanOrEqualTo(3));
    final decodedWrites = transportB.writes
        .map((bytes) => HmiFrame.tryDecode(bytes))
        .whereType<HmiFrame>()
        .toList();
    expect(decodedWrites, isNotEmpty);
    expect(
      decodedWrites.every((frame) => frame.function == hmisBamFunction),
      isTrue,
    );

    controller.dispose();
    await transportA.dispose();
    await transportB.dispose();
  });

  test('完整同步退化后仍保留快捷控制握手状态', () async {
    final transportA = _FakeSerialTransport();
    final transportB = _FakeSerialTransport();
    final controller = HmiController(transportA, transportB: transportB);

    final peer = _SessionBamPeer();
    transportB.onWrite = (bytes) async {
      final frame = peer.acceptWrite(bytes);
      if (frame == null) {
        return;
      }
      switch (frame.command) {
        case HmiSessionCommand.hello:
          transportB.emit(
            _sessionResponseFrame(
              sequence: frame.sequence,
              command: HmiSessionCommand.hello,
              payload: <int>[0x00, 0x01],
              address: peer.lastAddress,
            ),
          );
        case HmiSessionCommand.deviceInfo:
          transportB.emit(
            _sessionResponseFrame(
              sequence: frame.sequence,
              command: HmiSessionCommand.deviceInfo,
              payload: <int>[0x00, 0x02, 0x00, 0x00, 0x00],
              address: peer.lastAddress,
            ),
          );
        case HmiSessionCommand.getGroupList:
          transportB.emit(
            _sessionResponseFrame(
              sequence: frame.sequence,
              command: HmiSessionCommand.getGroupList,
              payload: <int>[0x00, 0x00, 0x00, 0x00],
              address: peer.lastAddress,
            ),
          );
        case HmiSessionCommand.getParamList:
          transportB.emit(
            _sessionResponseFrame(
              sequence: frame.sequence,
              command: HmiSessionCommand.getParamList,
              payload: <int>[0x00, 0x00, 0x00, 0x00],
              address: peer.lastAddress,
            ),
          );
        default:
          break;
      }
    };

    await controller.syncSessionCatalog();

    expect(controller.sessionState, HmiSessionClientState.degraded);
    expect(controller.sessionHandshakeReady, isTrue);
    expect(controller.sessionQuickControlReady, isTrue);

    controller.dispose();
    await transportA.dispose();
    await transportB.dispose();
  });

  test('Session 命令超时后按策略重试，Android 偶发首包丢失时仍可恢复', () async {
    final transportA = _FakeSerialTransport();
    final transportB = _FakeSerialTransport();
    final controller = HmiController(transportA, transportB: transportB);
    controller.updateRetryPolicy(
      const HmiRetryPolicy(timeoutMs: 20, maxRetries: 2, retryIntervalMs: 0),
    );

    var helloWrites = 0;
    var deviceInfoWrites = 0;
    final peer = _SessionBamPeer();
    transportB.onWrite = (bytes) async {
      final frame = peer.acceptWrite(bytes);
      if (frame == null) {
        return;
      }
      switch (frame.command) {
        case HmiSessionCommand.hello:
          helloWrites++;
          transportB.emit(
            _sessionResponseFrame(
              sequence: frame.sequence,
              command: HmiSessionCommand.hello,
              payload: <int>[0x00, 0x01],
              address: peer.lastAddress,
            ),
          );
        case HmiSessionCommand.deviceInfo:
          deviceInfoWrites++;
          if (deviceInfoWrites >= 2) {
            transportB.emit(
              _sessionResponseFrame(
                sequence: frame.sequence,
                command: HmiSessionCommand.deviceInfo,
                payload: <int>[0x00, 0x02, 0x00, 0x00, 0x00],
                address: peer.lastAddress,
              ),
            );
          }
        case HmiSessionCommand.getGroupList:
          transportB.emit(
            _sessionResponseFrame(
              sequence: frame.sequence,
              command: HmiSessionCommand.getGroupList,
              payload: <int>[0x00, 0x00, 0x00, 0x00],
              address: peer.lastAddress,
            ),
          );
        case HmiSessionCommand.getParamList:
          transportB.emit(
            _sessionResponseFrame(
              sequence: frame.sequence,
              command: HmiSessionCommand.getParamList,
              payload: <int>[0x00, 0x00, 0x00, 0x00],
              address: peer.lastAddress,
            ),
          );
        default:
          break;
      }
    };

    await controller.syncSessionCatalog();

    expect(helloWrites, 1);
    expect(deviceInfoWrites, 2);
    expect(controller.sessionHandshakeReady, isTrue);
    expect(controller.sessionState, HmiSessionClientState.degraded);

    controller.dispose();
    await transportA.dispose();
    await transportB.dispose();
  });

  test('端口 B 断连事件会立即清空 Session 状态', () async {
    final transportA = _FakeSerialTransport();
    final transportB = _FakeSerialTransport();
    final controller = HmiController(transportA, transportB: transportB);

    final peer = _SessionBamPeer();
    transportB.onWrite = (bytes) async {
      final frame = peer.acceptWrite(bytes);
      if (frame == null) {
        return;
      }
      switch (frame.command) {
        case HmiSessionCommand.hello:
          transportB.emit(
            _sessionResponseFrame(
              sequence: frame.sequence,
              command: HmiSessionCommand.hello,
              payload: <int>[0x00, 0x01],
              address: peer.lastAddress,
            ),
          );
        case HmiSessionCommand.deviceInfo:
          transportB.emit(
            _sessionResponseFrame(
              sequence: frame.sequence,
              command: HmiSessionCommand.deviceInfo,
              payload: <int>[0x00, 0x02, 0x00, 0x00, 0x00],
              address: peer.lastAddress,
            ),
          );
        case HmiSessionCommand.getGroupList:
          transportB.emit(
            _sessionResponseFrame(
              sequence: frame.sequence,
              command: HmiSessionCommand.getGroupList,
              payload: <int>[0x00, 0x00, 0x00, 0x00],
              address: peer.lastAddress,
            ),
          );
        case HmiSessionCommand.getParamList:
          transportB.emit(
            _sessionResponseFrame(
              sequence: frame.sequence,
              command: HmiSessionCommand.getParamList,
              payload: <int>[0x00, 0x00, 0x00, 0x00],
              address: peer.lastAddress,
            ),
          );
        default:
          break;
      }
    };

    await controller.syncSessionCatalog();
    expect(controller.sessionHandshakeReady, isTrue);

    await transportB.disconnect();
    await Future<void>.delayed(Duration.zero);

    expect(controller.sessionHandshakeReady, isFalse);
    expect(controller.sessionState, HmiSessionClientState.disconnected);
    expect(controller.sessionQuickControlReady, isFalse);

    controller.dispose();
    await transportA.dispose();
    await transportB.dispose();
  });

  test('端口 B 断连后会清理半包缓存，避免旧数据污染后续会话', () async {
    final transportA = _FakeSerialTransport();
    final transportB = _FakeSerialTransport();
    final controller = HmiController(transportA, transportB: transportB);

    final frame = _sessionLogFrame('SESSION_OK');
    final splitAt = frame.length ~/ 2;
    transportB.emit(frame.sublist(0, splitAt));
    await Future<void>.delayed(Duration.zero);

    await transportB.disconnect();
    await Future<void>.delayed(Duration.zero);

    transportB.emit(frame.sublist(splitAt));
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
