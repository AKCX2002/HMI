import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'serial_transport.dart';

/// Android USB Host 串口实现。
///
/// 当前通过 MethodChannel/EventChannel 对接原生 Kotlin + usb-serial-for-android。
class AndroidUsbSerialTransport implements SerialTransport {
  AndroidUsbSerialTransport() {
    _eventSubscription = _eventStream.listen(
      _handleNativeEvent,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Android USB 串口事件流异常: $error');
      },
    );
  }

  static const String methodChannelName = 'hmi_host/android_usb_serial/methods';
  static const String eventChannelName = 'hmi_host/android_usb_serial/events';

  static const MethodChannel _methodChannel = MethodChannel(methodChannelName);
  static const EventChannel _eventChannel = EventChannel(eventChannelName);

  static Stream<dynamic>? _sharedEventStream;
  static int _nextTransportId = 1;

  final StreamController<Uint8List> _incomingController =
      StreamController<Uint8List>.broadcast();
  final int _transportId = _nextTransportId++;

  StreamSubscription<dynamic>? _eventSubscription;
  bool _isConnected = false;

  static Stream<dynamic> get _eventStream {
    return _sharedEventStream ??=
        _eventChannel.receiveBroadcastStream().asBroadcastStream();
  }

  @override
  Future<List<String>> availablePorts() async {
    try {
      final List<dynamic>? ports = await _methodChannel.invokeListMethod<dynamic>(
        'listPorts',
      );
      if (ports == null) {
        return const <String>[];
      }
      return ports.map((dynamic item) => item.toString()).toList(growable: false);
    } on PlatformException catch (e) {
      throw StateError(e.message ?? 'Android USB 串口扫描失败');
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
    try {
      await _methodChannel.invokeMethod<void>('connect', <String, Object>{
        'transportId': _transportId,
        'portName': portName,
        'baudRate': baudRate,
        'dataBits': dataBits,
        'stopBits': stopBits,
        'parity': parity,
        'flowControl': flowControl,
      });
      _isConnected = true;
    } on PlatformException catch (e) {
      _isConnected = false;
      throw StateError(e.message ?? 'Android USB 串口连接失败');
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _methodChannel.invokeMethod<void>('disconnect', <String, Object>{
        'transportId': _transportId,
      });
    } on PlatformException catch (e) {
      throw StateError(e.message ?? 'Android USB 串口断开失败');
    } finally {
      _isConnected = false;
    }
  }

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<Uint8List> get incomingBytes => _incomingController.stream;

  @override
  Future<void> write(Uint8List bytes) async {
    if (!_isConnected) {
      throw StateError('串口未连接');
    }
    try {
      await _methodChannel.invokeMethod<int>('write', <String, Object>{
        'transportId': _transportId,
        'bytes': bytes,
      });
    } on PlatformException catch (e) {
      throw StateError(e.message ?? 'Android USB 串口写入失败');
    }
  }

  void _handleNativeEvent(dynamic event) {
    if (event is! Map<Object?, Object?>) {
      return;
    }
    final Object? transportId = event['transportId'];
    if (transportId is! int || transportId != _transportId) {
      return;
    }
    final String type = event['type']?.toString() ?? '';
    switch (type) {
      case 'data':
        final Object? rawData = event['data'];
        if (rawData is Uint8List) {
          _incomingController.add(rawData);
        } else if (rawData is List<Object?>) {
          final List<int> bytes = rawData
              .map((Object? value) => (value as num).toInt())
              .toList(growable: false);
          _incomingController.add(Uint8List.fromList(bytes));
        }
        break;
      case 'detached':
      case 'closed':
        _isConnected = false;
        break;
      default:
        break;
    }
  }

  /// 释放内部资源。
  Future<void> dispose() async {
    try {
      await disconnect();
    } catch (_) {
      // 析构路径忽略重复断开错误。
    }
    try {
      await _eventSubscription?.cancel();
    } catch (e) {
      debugPrint('取消 Android USB 串口事件订阅异常: $e');
    }
    _eventSubscription = null;
    try {
      await _incomingController.close();
    } catch (e) {
      debugPrint('关闭 Android USB 串口流控制器异常: $e');
    }
  }
}
