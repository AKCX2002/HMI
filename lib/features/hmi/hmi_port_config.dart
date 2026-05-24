import '../../core/protocol/crc_algorithm.dart';

/// USART 串口数据位。
enum HmiDataBits {
  bits5(5, '5'),
  bits6(6, '6'),
  bits7(7, '7'),
  bits8(8, '8');

  const HmiDataBits(this.value, this.label);
  final int value;
  final String label;
}

/// USART 串口停止位。
enum HmiStopBits {
  one(1, '1'),
  onePointFive(3, '1.5'), // flutter_libserialport: 3 = 1.5
  two(2, '2');

  const HmiStopBits(this.value, this.label);
  final int value;
  final String label;
}

/// USART 串口校验位。
enum HmiParity {
  none(0, '无'),
  odd(1, '奇校验'),
  even(2, '偶校验'),
  mark(3, 'Mark'),
  space(4, 'Space');

  const HmiParity(this.value, this.label);
  final int value;
  final String label;
}

/// USART 流控制。
enum HmiFlowControl {
  none(0, '无'),
  rtsCts(1, 'RTS/CTS'),
  xonXoff(2, 'XON/XOFF');

  const HmiFlowControl(this.value, this.label);
  final int value;
  final String label;
}

/// 单个串口连接配置。
class HmiPortConfig {
  /// 创建串口配置。
  ///
  /// [portName] 串口名称，如 `"COM3"` / `"/dev/ttyUSB0"`。
  /// [baudRate] 波特率，默认 115200。
  /// [dataBits] 数据位，默认 8。
  /// [stopBits] 停止位，默认 1。
  /// [parity] 校验位，默认无。
  /// [flowControl] 流控制，默认无。
  /// [crcAlgorithm] CRC 算法，默认 CRC16-Modbus。
  /// [label] 显示标签，如 `"端口 A（上位主控）"`。
  const HmiPortConfig({
    this.portName,
    this.baudRate = 115200,
    this.dataBits = HmiDataBits.bits8,
    this.stopBits = HmiStopBits.one,
    this.parity = HmiParity.none,
    this.flowControl = HmiFlowControl.none,
    this.crcAlgorithm = CrcAlgorithm.modbus,
    this.label = '',
  });

  /// 串口名称。
  final String? portName;

  /// 波特率。
  final int baudRate;

  /// 数据位。
  final HmiDataBits dataBits;

  /// 停止位。
  final HmiStopBits stopBits;

  /// 校验位。
  final HmiParity parity;

  /// 流控制。
  final HmiFlowControl flowControl;

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
    final pLabel = parity.shortLabel;
    final dbLabel = dataBits.label;
    final sbLabel = stopBits.label;
    final uart = '$baudRate/$dbLabel$pLabel$sbLabel';
    return label.isNotEmpty
        ? '$label: $port @ $uart ($crcName)'
        : '$port @ $uart ($crcName)';
  }

  /// 复制并更新部分字段。
  HmiPortConfig copyWith({
    String? portName,
    int? baudRate,
    HmiDataBits? dataBits,
    HmiStopBits? stopBits,
    HmiParity? parity,
    HmiFlowControl? flowControl,
    CrcAlgorithm? crcAlgorithm,
    String? label,
  }) {
    return HmiPortConfig(
      portName: portName ?? this.portName,
      baudRate: baudRate ?? this.baudRate,
      dataBits: dataBits ?? this.dataBits,
      stopBits: stopBits ?? this.stopBits,
      parity: parity ?? this.parity,
      flowControl: flowControl ?? this.flowControl,
      crcAlgorithm: crcAlgorithm ?? this.crcAlgorithm,
      label: label ?? this.label,
    );
  }
}

/// HmiParity 扩展：短标签用于摘要字符串。
extension HmiParityLabel on HmiParity {
  String get shortLabel {
    switch (this) {
      case HmiParity.none:
        return 'N';
      case HmiParity.odd:
        return 'O';
      case HmiParity.even:
        return 'E';
      case HmiParity.mark:
        return 'M';
      case HmiParity.space:
        return 'S';
    }
  }
}
