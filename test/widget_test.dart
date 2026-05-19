import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hmi_host/core/serial/serial_transport.dart';
import 'package:hmi_host/features/hmi/hmi_controller.dart';
import 'package:hmi_host/main.dart' show HmiHostApp;

class _FakeSerialTransport implements SerialTransport {
  final Stream<Uint8List> _stream = const Stream<Uint8List>.empty();

  @override
  Future<List<String>> availablePorts() async => const <String>['COM1'];

  @override
  Future<void> connect({
    required String portName,
    required int baudRate,
  }) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Stream<Uint8List> get incomingBytes => _stream;

  @override
  bool get isConnected => false;

  @override
  Future<void> write(Uint8List bytes) async {}
}

void main() {
  testWidgets('HMI dashboard renders title', (WidgetTester tester) async {
    final app = HmiHostApp(controller: HmiController(_FakeSerialTransport()));
    await tester.pumpWidget(app);

    expect(find.text('上位机控制台'), findsOneWidget);
    expect(find.text('连接与指令'), findsOneWidget);
  });
}
