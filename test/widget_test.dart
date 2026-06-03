import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hmi_host/core/serial/serial_transport.dart';
import 'package:hmi_host/features/hmi/hmi_controller.dart';
import 'package:hmi_host/features/hmi/hmi_hmis_bam.dart';
import 'package:hmi_host/features/hmi/hmi_session_frame.dart';
import 'package:hmi_host/main.dart' show HmiHostApp;

class _FakeSerialTransport implements SerialTransport {
  _FakeSerialTransport({List<String>? ports})
    : _ports = ports ?? const <String>['COM1'];

  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast();
  final StreamController<SerialConnectionState> _connectionStates =
      StreamController<SerialConnectionState>.broadcast();
  final List<String> _ports;
  bool _connected = false;
  Future<void> Function(Uint8List bytes)? onWrite;

  void emit(List<int> bytes) {
    _incoming.add(Uint8List.fromList(bytes));
  }

  @override
  Future<List<String>> availablePorts() async => _ports;

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
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _connectionStates.add(SerialConnectionState.disconnected);
  }

  @override
  Stream<Uint8List> get incomingBytes => _incoming.stream;

  @override
  bool get isConnected => _connected;

  @override
  Stream<SerialConnectionState> get connectionStates =>
      _connectionStates.stream;

  @override
  Future<void> write(Uint8List bytes) async {
    await onWrite?.call(bytes);
  }

  Future<void> dispose() async {
    await _connectionStates.close();
    await _incoming.close();
  }
}

List<int> _sessionLogFrame(String text) {
  final session = HmiSessionFrame(
    type: HmiSessionFrameType.log,
    sequence: 1,
    command: HmiSessionCommand.logPush,
    payload: Uint8List.fromList(<int>[3, ...text.codeUnits]),
  ).encode();
  return HmisBamFrameBuilder()
      .encodePayload(address: 0xFA, payload: session)
      .expand((frame) => frame.encode())
      .toList();
}

void main() {
  testWidgets('HMI dashboard renders title', (WidgetTester tester) async {
    final transportA = _FakeSerialTransport();
    final transportB = _FakeSerialTransport();
    final controller = HmiController(transportA, transportB: transportB);
    final app = HmiHostApp(controller: controller);
    await tester.pumpWidget(app);

    expect(find.text('打包机'), findsOneWidget);
    expect(find.text('USART3调试'), findsOneWidget);

    controller.dispose();
    await transportA.dispose();
    await transportB.dispose();
  });

  testWidgets('USART1 page exposes three session sub pages', (
    WidgetTester tester,
  ) async {
    final transportA = _FakeSerialTransport();
    final transportB = _FakeSerialTransport();
    final controller = HmiController(transportA, transportB: transportB);
    final app = HmiHostApp(controller: controller);
    await tester.pumpWidget(app);

    await tester.tap(find.text('USART1会话').last);
    await tester.pumpAndSettle();

    expect(find.text('参数调节'), findsAtLeastNWidgets(1));
    expect(find.text('系统状态'), findsAtLeastNWidgets(1));
    expect(find.text('日志监控'), findsAtLeastNWidgets(1));

    controller.dispose();
    await transportA.dispose();
    await transportB.dispose();
  });

  testWidgets('栈统计页显示总览卡片与任务表格', (WidgetTester tester) async {
    final transportA = _FakeSerialTransport();
    final transportB = _FakeSerialTransport();
    final controller = HmiController(transportA, transportB: transportB);
    final app = HmiHostApp(controller: controller);
    await tester.pumpWidget(app);

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
    await tester.pump();

    await tester.tap(find.text('栈水位统计').last);
    await tester.pumpAndSettle();

    expect(find.text('总栈'), findsAtLeastNWidgets(1));
    expect(find.text('当前总已占用'), findsAtLeastNWidgets(1));
    expect(find.text('当前总剩余'), findsAtLeastNWidgets(1));
    expect(find.text('最危险任务'), findsAtLeastNWidgets(1));
    expect(find.text('ProtoTask'), findsOneWidget);
    expect(find.text('MonitorTask'), findsAtLeastNWidgets(1));

    controller.dispose();
    await transportA.dispose();
    await transportB.dispose();
  });

  testWidgets('栈统计空态按 USART1 HMIS-BAM Session 日志口径提示', (
    WidgetTester tester,
  ) async {
    final transportA = _FakeSerialTransport();
    final transportB = _FakeSerialTransport();
    final controller = HmiController(transportA, transportB: transportB);
    final app = HmiHostApp(controller: controller);
    await tester.pumpWidget(app);

    await tester.tap(find.text('栈水位统计').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('USART1 HMIS-BAM Session 日志'), findsOneWidget);
    expect(find.textContaining('等待固件输出 STACK_SNAPSHOT'), findsNothing);

    controller.dispose();
    await transportA.dispose();
    await transportB.dispose();
  });

  testWidgets('超长 Android 串口名在窄布局下不触发溢出', (WidgetTester tester) async {
    const longPortName =
        'USB Serial Device with Very Long Android Friendly Name /dev/bus/usb/001/002';
    final transportA = _FakeSerialTransport(
      ports: const <String>[longPortName],
    );
    final transportB = _FakeSerialTransport();
    final controller = HmiController(transportA, transportB: transportB);
    await controller.refreshPortsA();
    controller.setPortA(longPortName);

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final app = HmiHostApp(controller: controller);
    await tester.pumpWidget(app);
    await tester.pump();

    final portTextWidgets = tester
        .widgetList<Text>(find.text(longPortName))
        .where((Text widget) => widget.data == longPortName)
        .toList();
    expect(portTextWidgets, isNotEmpty);
    expect(
      portTextWidgets.any(
        (Text widget) =>
            widget.maxLines == 1 && widget.overflow == TextOverflow.ellipsis,
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);

    controller.dispose();
    await transportA.dispose();
    await transportB.dispose();
  });

  testWidgets('中等窄布局下隐藏 CRC 控件并为长串口名保留更多宽度', (WidgetTester tester) async {
    const longPortName =
        'USB Serial Device with Very Long Android Friendly Name /dev/bus/usb/001/002';
    final transportA = _FakeSerialTransport(
      ports: const <String>[longPortName],
    );
    final transportB = _FakeSerialTransport();
    final controller = HmiController(transportA, transportB: transportB);
    await controller.refreshPortsA();
    controller.setPortA(longPortName);

    tester.view.physicalSize = const Size(560, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final app = HmiHostApp(controller: controller);
    await tester.pumpWidget(app);
    await tester.pump();

    expect(find.text('CRC'), findsNothing);
    expect(find.text('DGUS'), findsNothing);
    expect(tester.takeException(), isNull);

    controller.dispose();
    await transportA.dispose();
    await transportB.dispose();
  });

  testWidgets('非预设波特率也能安全显示在下拉框中', (WidgetTester tester) async {
    final transportA = _FakeSerialTransport();
    final transportB = _FakeSerialTransport();
    final controller = HmiController(transportA, transportB: transportB);
    controller.setBaudRateA(250000);

    final app = HmiHostApp(controller: controller);
    await tester.pumpWidget(app);
    await tester.pump();

    expect(find.text('250000'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);

    controller.dispose();
    await transportA.dispose();
    await transportB.dispose();
  });

  testWidgets('可直接在波特率控件中输入新值', (WidgetTester tester) async {
    final transportA = _FakeSerialTransport();
    final transportB = _FakeSerialTransport();
    final controller = HmiController(transportA, transportB: transportB);

    final app = HmiHostApp(controller: controller);
    await tester.pumpWidget(app);
    await tester.pump();

    await tester.enterText(find.byType(TextFormField).first, '250000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(controller.portAConfig.baudRate, 250000);
    expect(find.text('250000'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);

    controller.dispose();
    await transportA.dispose();
    await transportB.dispose();
  });
}
