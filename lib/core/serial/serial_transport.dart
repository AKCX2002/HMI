import 'dart:typed_data';

/// 与平台无关的串口抽象层。
///
/// 协议层与业务层应依赖该接口，而不是直接依赖具体插件实现。
abstract class SerialTransport {
  /// 获取当前平台可用串口名称列表。
  Future<List<String>> availablePorts();

  /// 以指定参数打开串口。
  Future<void> connect({required String portName, required int baudRate});

  /// 关闭当前串口连接。
  Future<void> disconnect();

  /// 当前是否已连接。
  bool get isConnected;

  /// 串口原始字节流。
  Stream<Uint8List> get incomingBytes;

  /// 发送原始字节到设备。
  Future<void> write(Uint8List bytes);
}
