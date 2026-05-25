import 'dart:typed_data';

enum SerialConnectionState {
  connected,
  disconnected,
}

/// 与平台无关的串口抽象层。
///
/// 协议层与业务层应依赖该接口，而不是直接依赖具体插件实现。
abstract class SerialTransport {
  /// 获取当前平台可用串口名称列表。
  Future<List<String>> availablePorts();

  /// 以指定参数打开串口。
  ///
  /// [portName] 串口设备名 (如 `/dev/ttyUSB0`, `COM3`)。
  /// [baudRate] 波特率。
  /// [dataBits] 数据位，默认 8。
  /// [stopBits] 停止位，默认 1 (取值 1/3/2，其中 3 表示 1.5)。
  /// [parity] 校验位，默认 0 (无校验)。
  /// [flowControl] 流控制，默认 0 (无)。
  Future<void> connect({
    required String portName,
    required int baudRate,
    int dataBits = 8,
    int stopBits = 1,
    int parity = 0,
    int flowControl = 0,
  });

  /// 关闭当前串口连接。
  Future<void> disconnect();

  /// 当前是否已连接。
  bool get isConnected;

  /// 串口连接状态变化。
  Stream<SerialConnectionState> get connectionStates;

  /// 串口原始字节流。
  Stream<Uint8List> get incomingBytes;

  /// 发送原始字节到设备。
  Future<void> write(Uint8List bytes);
}
