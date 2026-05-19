import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'serial_transport.dart';

/// 基于 `flutter_libserialport` 的串口实现。
///
/// 说明：
/// - Web 平台不支持本地 UART。
/// - 主要用于桌面/移动原生运行时。
class SerialTransportImpl implements SerialTransport {
  final StreamController<Uint8List> _incomingController =
      StreamController<Uint8List>.broadcast();

  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _readerSubscription;

  @override
  Future<List<String>> availablePorts() async {
    if (kIsWeb) {
      return const <String>[];
    }
    try {
      return SerialPort.availablePorts;
    } catch (e) {
      debugPrint('扫描串口失败: $e');
      return const <String>[];
    }
  }

  @override
  Future<void> connect({
    required String portName,
    required int baudRate,
  }) async {
    await disconnect();

    if (kIsWeb) {
      throw StateError('Web 平台不支持本地串口访问');
    }

    final port = SerialPort(portName);
    final opened = port.openReadWrite();
    if (!opened) {
      final message = SerialPort.lastError?.toString() ?? '无法打开串口 $portName';
      throw StateError(message);
    }

    final config = SerialPortConfig();
    config.baudRate = baudRate;
    config.bits = 8;
    config.stopBits = 1;
    config.parity = SerialPortParity.none;
    config.setFlowControl(SerialPortFlowControl.none);
    port.config = config;

    _reader = SerialPortReader(port);
    _readerSubscription = _reader!.stream.listen(
      (data) {
        _incomingController.add(Uint8List.fromList(data));
      },
      onError: (Object error) {
        debugPrint('串口读取错误: $error');
      },
    );
    _port = port;
  }

  @override
  Future<void> disconnect() async {
    await _readerSubscription?.cancel();
    _readerSubscription = null;
    _reader = null;
    if (_port != null) {
      _port!.close();
      _port!.dispose();
      _port = null;
    }
  }

  @override
  bool get isConnected => _port?.isOpen ?? false;

  @override
  Stream<Uint8List> get incomingBytes => _incomingController.stream;

  @override
  Future<void> write(Uint8List bytes) async {
    final port = _port;
    if (port == null || !port.isOpen) {
      throw StateError('串口未连接');
    }
    final written = port.write(bytes);
    if (written < bytes.length) {
      throw StateError('串口发送不完整: $written/${bytes.length}');
    }
  }

  /// 释放内部流与底层串口资源。
  Future<void> dispose() async {
    await disconnect();
    await _incomingController.close();
  }
}
