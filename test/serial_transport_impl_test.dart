import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hmi_host/core/serial/android_usb_serial_transport.dart';
import 'package:hmi_host/core/serial/desktop_serial_transport.dart';
import 'package:hmi_host/core/serial/serial_transport_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('serial backend selection', () {
    test('Android 平台默认选择 Android USB Host 后端', () {
      final backend = detectDefaultSerialTransportBackend(
        isWebOverride: false,
        platformOverride: TargetPlatform.android,
      );

      expect(backend, SerialTransportBackend.androidUsb);
    });

    test('桌面平台默认选择 libserialport 后端', () {
      final backend = detectDefaultSerialTransportBackend(
        isWebOverride: false,
        platformOverride: TargetPlatform.linux,
      );

      expect(backend, SerialTransportBackend.desktop);
    });

    test('显式指定 Android 后端时创建 AndroidUsbSerialTransport', () {
      final transport = SerialTransportImpl(
        backend: SerialTransportBackend.androidUsb,
      );

      expect(transport.debugDelegate, isA<AndroidUsbSerialTransport>());
    });

    test('显式指定桌面后端时创建 DesktopSerialTransport', () {
      final transport = SerialTransportImpl(
        backend: SerialTransportBackend.desktop,
      );

      expect(transport.debugDelegate, isA<DesktopSerialTransport>());
    });
  });

  group('android usb transport method channel', () {
    const MethodChannel methodChannel = MethodChannel(
      AndroidUsbSerialTransport.methodChannelName,
    );
    final List<MethodCall> calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (MethodCall call) async {
            calls.add(call);
            switch (call.method) {
              case 'listPorts':
                return <String>['DAPLink CDC ACM'];
              case 'connect':
              case 'disconnect':
                return null;
              case 'write':
                return 3;
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, null);
    });

    test('availablePorts/connect/write/disconnect 调用原生 USB Host 通道', () async {
      final transport = AndroidUsbSerialTransport();

      final ports = await transport.availablePorts();
      await transport.connect(portName: 'DAPLink CDC ACM', baudRate: 9600);
      await transport.write(Uint8List.fromList(<int>[0x01, 0x02, 0x03]));
      await transport.disconnect();

      expect(ports, <String>['DAPLink CDC ACM']);
      expect(calls.map((MethodCall call) => call.method).toList(), <String>[
        'listPorts',
        'connect',
        'write',
        'disconnect',
      ]);
      expect(
        (calls[1].arguments as Map<Object?, Object?>)['portName'],
        'DAPLink CDC ACM',
      );
      expect((calls[1].arguments as Map<Object?, Object?>)['baudRate'], 9600);
      expect((calls[2].arguments as Map<Object?, Object?>)['bytes'], isA<Uint8List>());
    });

    test('native error 事件会立刻清除连接状态', () async {
      final transport = AndroidUsbSerialTransport();

      await transport.connect(portName: 'DAPLink CDC ACM', baudRate: 9600);
      expect(transport.isConnected, isTrue);

      transport.debugHandleNativeEvent(<Object?, Object?>{
        'transportId': transport.debugTransportId,
        'type': 'error',
        'message': 'write failed',
      });

      expect(transport.isConnected, isFalse);
    });
  });
}
