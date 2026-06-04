import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'serial_transport.dart';

/// 桌面平台串口实现，基于 `flutter_libserialport`。
class DesktopSerialTransport implements SerialTransport {
  final StreamController<Uint8List> _incomingController =
      StreamController<Uint8List>.broadcast();
  final StreamController<SerialConnectionState> _connectionStateController =
      StreamController<SerialConnectionState>.broadcast();

  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _readerSubscription;

  void _handleIncomingBytes(Uint8List bytes) {
    /* libserialport 桌面端可能复用底层读缓冲；转一份稳定副本再上抛，
       避免 HMI 协议层在长帧/连续分页场景读到后续覆盖的数据。 */
    _incomingController.add(Uint8List.fromList(bytes));
  }

  String _errnoHint(int code) {
    switch (code) {
      case 2:
        return '设备不存在';
      case 5:
        return 'I/O 错误';
      case 13:
        return '权限不足';
      case 16:
        return '设备忙';
      default:
        return '系统错误';
    }
  }

  String _formatOpenError(String portName, SerialPortError? error) {
    if (error == null) {
      return '无法打开串口 $portName';
    }
    final hint = _errnoHint(error.errorCode);
    return '无法打开串口 $portName（$hint, errno=${error.errorCode}）';
  }

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
        final err = SerialPort.lastError;
        debugPrint('打开串口失败原始错误: $err');
        throw StateError(_formatOpenError(portName, err));
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
        _handleIncomingBytes,
        onError: (Object error) {
          debugPrint('桌面串口读取错误: $error');
          unawaited(disconnect());
        },
      );
      _port = port;
      _connectionStateController.add(SerialConnectionState.connected);
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
    final wasConnected = _port?.isOpen ?? false;
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
    if (wasConnected) {
      _connectionStateController.add(SerialConnectionState.disconnected);
    }
  }

  @override
  bool get isConnected => _port?.isOpen ?? false;

  @override
  Stream<SerialConnectionState> get connectionStates =>
      _connectionStateController.stream;

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
    try {
      await _connectionStateController.close();
    } catch (e) {
      debugPrint('关闭桌面串口状态流异常: $e');
    }
  }

  @visibleForTesting
  void debugHandleIncomingBytes(Uint8List bytes) {
    _handleIncomingBytes(bytes);
  }
}
