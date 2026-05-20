import '../../core/protocol/hmi_frame.dart';

/// 当前 HMI 仅保留打包机协议(0x40~0x4C)与自定义帧。
enum HmiCommandCode {
  packer(0x40, '打包机命令'),
  custom(0x00, '自定义帧');

  const HmiCommandCode(this.code, this.label);
  final int code;
  final String label;
}

enum HmiPackerFunction {
  control(0x40, '打包机启停'),
  status(0x41, '打包机状态'),
  triggerBag(0x42, '触发出袋'),
  triggerSeal(0x43, '触发封口'),
  triggerDeliver(0x44, '触发投料'),
  clearFlag(0x45, '清除标志'),
  alarmQuery(0x46, '报警查询'),
  printerForward(0x47, '打印机透传'),
  version(0x48, '版本查询'),
  resetFault(0x49, '故障复位'),
  stepperJog(0x4A, '步进点动'),
  dcMotor1Jog(0x4B, '直流1点动'),
  dcMotor2Jog(0x4C, '直流2点动');

  const HmiPackerFunction(this.code, this.label);
  final int code;
  final String label;
}

class HmiRetryPolicy {
  const HmiRetryPolicy({
    this.maxRetries = 1,
    this.timeoutMs = 1200,
    this.retryIntervalMs = 200,
  });

  final int maxRetries;
  final int timeoutMs;
  final int retryIntervalMs;

  HmiRetryPolicy copyWith({
    int? maxRetries,
    int? timeoutMs,
    int? retryIntervalMs,
  }) {
    return HmiRetryPolicy(
      maxRetries: maxRetries ?? this.maxRetries,
      timeoutMs: timeoutMs ?? this.timeoutMs,
      retryIntervalMs: retryIntervalMs ?? this.retryIntervalMs,
    );
  }
}

class HmiCommandRequest {
  HmiCommandRequest({
    required this.command,
    required this.frame,
    required this.expectedFunctions,
    this.note,
    String? label,
  }) : label = label ?? command.label;

  final HmiCommandCode command;
  final HmiFrame frame;
  final Set<int> expectedFunctions;
  final String? note;
  final String label;
}

class HmiDecodedFrame {
  const HmiDecodedFrame({
    required this.title,
    required this.summary,
    required this.rawDataHex,
    this.errorCode,
  });

  final String title;
  final String summary;
  final String rawDataHex;
  final int? errorCode;
}

const Map<int, Set<int>> kRequestToExpectedResponseFunctions = <int, Set<int>>{
  0x40: <int>{0x40},
  0x41: <int>{0x41},
  0x42: <int>{0x42},
  0x43: <int>{0x43},
  0x44: <int>{0x44},
  0x45: <int>{0x45},
  0x46: <int>{0x46},
  0x47: <int>{0x47},
  0x48: <int>{0x48},
  0x49: <int>{0x49},
  0x4A: <int>{0x4A},
  0x4B: <int>{0x4B},
  0x4C: <int>{0x4C},
};

String toHex2(int value) =>
    value.toRadixString(16).padLeft(2, '0').toUpperCase();

String payloadToHex(List<int> data) => data.map(toHex2).join(' ');

String _yesNo(int value) => value == 0 ? '否' : '是';

String _packerResultName(int value) {
  return switch (value) {
    0x00 => '成功',
    0x01 => '无效功能码',
    0x02 => '无效参数',
    0x03 => '设备忙',
    0x04 => '状态拒绝',
    0x05 => '报警激活',
    0x06 => '硬件故障',
    0x07 => '超时',
    0x08 => '不支持',
    _ => '未知错误',
  };
}

String packerResultName(int value) => _packerResultName(value);

String _clearFlagName(int value) {
  return switch (value) {
    0x01 => '出袋完成',
    0x02 => '封口完成',
    0x03 => '投料完成',
    _ => '未知标志',
  };
}

HmiDecodedFrame decodeHmiFrame(HmiFrame frame) {
  final d = frame.data;
  final raw = payloadToHex(d);

  switch (frame.function) {
    case 0x40:
      return HmiDecodedFrame(
        title: '打包机启停响应(0x40)',
        summary:
            '结果=${_packerResultName(d[0])} 运行=${d[1]} 报警=0x${toHex2(d[2])}',
        rawDataHex: raw,
      );
    case 0x41:
      return HmiDecodedFrame(
        title: '打包机状态(0x41)',
        summary:
            '结果=${_packerResultName(d[0])} 运行=${d[1]} busy=0x${toHex2(d[3])} '
            '出袋=${d[4]} 封口=${d[5]} 投料=${d[6]} 报警=0x${toHex2(d[10])}',
        rawDataHex: raw,
      );
    case 0x42:
      return HmiDecodedFrame(
        title: '出袋触发响应(0x42)',
        summary:
            '结果=${_packerResultName(d[0])} 锁存=${d[1]} 报警=0x${toHex2(d[2])}',
        rawDataHex: raw,
      );
    case 0x43:
      return HmiDecodedFrame(
        title: '封口触发响应(0x43)',
        summary:
            '结果=${_packerResultName(d[0])} 锁存=${d[1]} 报警=0x${toHex2(d[2])}',
        rawDataHex: raw,
      );
    case 0x44:
      return HmiDecodedFrame(
        title: '投料触发响应(0x44)',
        summary:
            '结果=${_packerResultName(d[0])} 锁存=${d[1]} 报警=0x${toHex2(d[2])}',
        rawDataHex: raw,
      );
    case 0x45:
      return HmiDecodedFrame(
        title: '清除标志响应(0x45)',
        summary: '结果=${_packerResultName(d[0])} 标志=${_clearFlagName(d[1])}',
        rawDataHex: raw,
      );
    case 0x46:
      return HmiDecodedFrame(
        title: '打包机报警(0x46)',
        summary:
            '结果=${_packerResultName(d[0])} 报警=0x${toHex2(d[1])} 锁存=${_yesNo(d[2])}',
        rawDataHex: raw,
      );
    case 0x47:
      return HmiDecodedFrame(
        title: '打印机透传响应(0x47)',
        summary:
            '结果=${_packerResultName(d[0])} rsp_cmd=0x${toHex2(d[1])} len=${d[2]}',
        rawDataHex: raw,
      );
    case 0x48:
      return HmiDecodedFrame(
        title: '版本查询响应(0x48)',
        summary:
            '结果=${_packerResultName(d[0])} ver=${d[1]}.${d[2]} cap=0x${toHex2(d[3])}',
        rawDataHex: raw,
      );
    case 0x49:
      return HmiDecodedFrame(
        title: '故障复位响应(0x49)',
        summary:
            '结果=${_packerResultName(d[0])} 报警=0x${toHex2(d[1])} 锁存=${_yesNo(d[2])}',
        rawDataHex: raw,
      );
    case 0x4A:
      return HmiDecodedFrame(
        title: '步进点动响应(0x4A)',
        summary:
            '结果=${_packerResultName(d[0])} 电机=${d[1]} 方向=${d[2]} 脉冲=${(d[3] << 8) | d[4]}',
        rawDataHex: raw,
      );
    case 0x4B:
      return HmiDecodedFrame(
        title: '直流1点动响应(0x4B)',
        summary:
            '结果=${_packerResultName(d[0])} 电机=${d[1]} 方向=${d[2]} 时长=${(d[3] << 8) | d[4]}ms',
        rawDataHex: raw,
      );
    case 0x4C:
      return HmiDecodedFrame(
        title: '直流2点动响应(0x4C)',
        summary:
            '结果=${_packerResultName(d[0])} 电机=${d[1]} 方向=${d[2]} 时长=${(d[3] << 8) | d[4]}ms',
        rawDataHex: raw,
      );
    default:
      return HmiDecodedFrame(
        title: '未知响应(0x${toHex2(frame.function)})',
        summary: '原始数据: $raw',
        rawDataHex: raw,
      );
  }
}
