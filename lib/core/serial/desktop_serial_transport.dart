import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'serial_transport.dart';

/// 桌面平台串口实现，基于 `flutter_libserialport`。
class DesktopSerialTransport implements SerialTransport {
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
      debugPrint('扫描桌面串口失败: $e');
      return const <String>[];
    }
  }

  @override
  Future<void> connect({
    required String portName,
    required int baudRate,
    int dataBits = 8,
    int stopBits = 1,
    int parity = 0,
    int flowControl = 0,
  }) async {
    await disconnect();

    if (kIsWeb) {
      throw StateError('Web 平台不支持本地串口访问');
    }

    final port = SerialPort(portName);
    try {
      final opened = port.openReadWrite();
      if (!opened) {
        final message =
            SerialPort.lastError?.toString() ?? '无法打开串口 $portName';
        throw StateError(message);
      }

      final config = SerialPortConfig();
      config.baudRate = baudRate;
      config.bits = dataBits;
      config.stopBits = stopBits;
      config.parity = parity;
      config.setFlowControl(flowControl);
      port.config = config;

      _reader = SerialPortReader(port);
      _readerSubscription = _reader!.stream.listen(
        _incomingController.add,
        onError: (Object error) {
          debugPrint('桌面串口读取错误: $error');
        },
      );
      _port = port;
    } catch (e) {
      _readerSubscription?.cancel();
      _readerSubscription = null;
      _reader = null;
      port.dispose();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _readerSubscription?.cancel();
    } catch (e) {
      debugPrint('取消桌面串口读取订阅异常: $e');
    }
    _readerSubscription = null;
    _reader = null;
    if (_port != null) {
      try {
        _port!.close();
      } catch (e) {
        debugPrint('关闭桌面串口异常: $e');
      }
      try {
        _port!.dispose();
      } catch (e) {
        debugPrint('释放桌面串口资源异常: $e');
      }
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
    try {
      final written = port.write(bytes);
      if (written < bytes.length) {
        throw StateError('串口发送不完整: $written/${bytes.length}');
      }
    } on StateError {
      rethrow;
    } catch (e) {
      throw StateError('串口写入失败: $e');
    }
  }

  /// 释放内部流与底层串口资源。
  Future<void> dispose() async {
    await disconnect();
    try {
      await _incomingController.close();
    } catch (e) {
      debugPrint('关闭桌面串口流控制器异常: $e');
    }
  }
}
