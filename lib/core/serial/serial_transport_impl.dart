import 'package:flutter/foundation.dart';

import 'android_usb_serial_transport.dart';
import 'desktop_serial_transport.dart';
import 'serial_transport.dart';

enum SerialTransportBackend {
  auto,
  desktop,
  androidUsb,
}

SerialTransportBackend detectDefaultSerialTransportBackend({
  bool? isWebOverride,
  TargetPlatform? platformOverride,
}) {
  final bool isWeb = isWebOverride ?? kIsWeb;
  if (isWeb) {
    return SerialTransportBackend.desktop;
  }
  final TargetPlatform platform = platformOverride ?? defaultTargetPlatform;
  if (platform == TargetPlatform.android) {
    return SerialTransportBackend.androidUsb;
  }
  return SerialTransportBackend.desktop;
}

SerialTransport _createSerialTransport(SerialTransportBackend backend) {
  final SerialTransportBackend resolvedBackend =
      backend == SerialTransportBackend.auto
      ? detectDefaultSerialTransportBackend()
      : backend;
  switch (resolvedBackend) {
    case SerialTransportBackend.androidUsb:
      return AndroidUsbSerialTransport();
    case SerialTransportBackend.desktop:
    case SerialTransportBackend.auto:
      return DesktopSerialTransport();
  }
}

/// 基于平台自动分流的串口实现入口。
class SerialTransportImpl implements SerialTransport {
  SerialTransportImpl({SerialTransportBackend backend = SerialTransportBackend.auto})
    : _delegate = _createSerialTransport(backend);

  final SerialTransport _delegate;

  @visibleForTesting
  SerialTransport get debugDelegate => _delegate;

  @override
  Future<List<String>> availablePorts() => _delegate.availablePorts();

  @override
  Future<void> connect({
    required String portName,
    required int baudRate,
    int dataBits = 8,
    int stopBits = 1,
    int parity = 0,
    int flowControl = 0,
  }) {
    return _delegate.connect(
      portName: portName,
      baudRate: baudRate,
      dataBits: dataBits,
      stopBits: stopBits,
      parity: parity,
      flowControl: flowControl,
    );
  }

  @override
  Future<void> disconnect() => _delegate.disconnect();

  @override
  bool get isConnected => _delegate.isConnected;

  @override
  Stream<Uint8List> get incomingBytes => _delegate.incomingBytes;

  @override
  Future<void> write(Uint8List bytes) => _delegate.write(bytes);
}
