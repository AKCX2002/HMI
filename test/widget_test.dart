import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hmi_host/core/serial/serial_transport.dart';
import 'package:hmi_host/features/hmi/hmi_controller.dart';
import 'package:hmi_host/features/hmi/hmi_session_frame.dart';
import 'package:hmi_host/main.dart' show HmiHostApp;

class _FakeSerialTransport implements SerialTransport {
  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast();

  void emit(List<int> bytes) {
    _incoming.add(Uint8List.fromList(bytes));
  }

  @override
  Future<List<String>> availablePorts() async => const <String>['COM1'];

  @override
  Future<void> connect({
    required String portName,
    required int baudRate,
    int dataBits = 8,
    int stopBits = 1,
    int parity = 0,
    int flowControl = 0,
  }) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Stream<Uint8List> get incomingBytes => _incoming.stream;

  @override
  bool get isConnected => false;

  @override
  Future<void> write(Uint8List bytes) async {}

  Future<void> dispose() async {
    await _incoming.close();
  }
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
  testWidgets('HMI dashboard renders title', (WidgetTester tester) async {
    final transportA = _FakeSerialTransport();
    final transportB = _FakeSerialTransport();
    final app = HmiHostApp(
      controller: HmiController(transportA, transportB: transportB),
    );
    await tester.pumpWidget(app);

    expect(find.text('打包机'), findsOneWidget);
    expect(find.text('USART3调试'), findsOneWidget);

    await transportA.dispose();
    await transportB.dispose();
  });

  testWidgets('USART1 page exposes three session sub pages', (
    WidgetTester tester,
  ) async {
    final transportA = _FakeSerialTransport();
    final transportB = _FakeSerialTransport();
    final app = HmiHostApp(
      controller: HmiController(transportA, transportB: transportB),
    );
    await tester.pumpWidget(app);

    await tester.tap(find.text('USART1会话').last);
    await tester.pumpAndSettle();

    expect(find.text('参数调节'), findsAtLeastNWidgets(1));
    expect(find.text('系统状态'), findsAtLeastNWidgets(1));
    expect(find.text('日志监控'), findsAtLeastNWidgets(1));

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

  testWidgets('栈统计空态按 USART1 Session 日志口径提示', (WidgetTester tester) async {
    final transportA = _FakeSerialTransport();
    final transportB = _FakeSerialTransport();
    final controller = HmiController(transportA, transportB: transportB);
    final app = HmiHostApp(controller: controller);
    await tester.pumpWidget(app);

    await tester.tap(find.text('栈水位统计').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('USART1 Session 日志'), findsOneWidget);
    expect(find.textContaining('等待固件输出 STACK_SNAPSHOT'), findsNothing);

    controller.dispose();
    await transportA.dispose();
    await transportB.dispose();
  });
}
