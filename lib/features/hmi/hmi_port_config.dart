import '../../core/protocol/crc_algorithm.dart';

/// 单个串口连接配置。
class HmiPortConfig {
  /// 创建串口配置。
  ///
  /// [portName] 串口名称，如 `"COM3"` / `"/dev/ttyUSB0"`。
  /// [baudRate] 波特率，默认 115200。
  /// [crcAlgorithm] CRC 算法，默认 CRC16-Modbus。
  /// [label] 显示标签，如 `"端口 A（上位主控）"`。
  const HmiPortConfig({
    this.portName,
    this.baudRate = 115200,
    this.crcAlgorithm = CrcAlgorithm.modbus,
    this.label = '',
  });

  /// 串口名称。
  final String? portName;

  /// 波特率。
  final int baudRate;

  /// CRC 算法。
  final CrcAlgorithm crcAlgorithm;

  /// 显示标签。
  final String label;

  /// 是否已配置有效串口名称。
  bool get isValid => portName != null && portName!.isNotEmpty;

  /// 返回带标签的摘要字符串。
  String get summary {
    final port = portName ?? '（未选择）';
    final crcName = crcAlgorithm.displayName;
    return label.isNotEmpty
        ? '$label: $port @ $baudRate ($crcName)'
        : '$port @ $baudRate ($crcName)';
  }

  /// 复制并更新部分字段。
  HmiPortConfig copyWith({
    String? portName,
    int? baudRate,
    CrcAlgorithm? crcAlgorithm,
    String? label,
  }) {
    return HmiPortConfig(
      portName: portName ?? this.portName,
      baudRate: baudRate ?? this.baudRate,
      crcAlgorithm: crcAlgorithm ?? this.crcAlgorithm,
      label: label ?? this.label,
    );
  }
}
