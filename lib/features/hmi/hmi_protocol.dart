import '../../core/protocol/hmi_frame.dart';

/// 协议文档对应的高层功能码枚举。
enum HmiCommandCode {
  orderSend(0x01, '订单下发'),
  packSeal(0x03, '打包封口'),
  store(0x05, '储物格存放'),
  pickupUnlock(0x07, '取货开锁'),
  statusQuery(0x09, '状态查询'),
  deviceTest(0x0B, '设备测试'),
  returnGoods(0x0C, '退货'),
  initQuery(0x10, '初始化查询');

  const HmiCommandCode(this.code, this.label);
  final int code;
  final String label;
}

enum HmiPackerFunction {
  control(0x40, '打包机启停'),
  status(0x41, '打包机状态'),
  triggerBag(0x42, '触发出袋'),
  triggerSeal(0x43, '触发封口'),
  avoidCtrl(0x44, '避让控制'),
  clearFlag(0x45, '清除标志'),
  alarmQuery(0x46, '报警查询'),
  heartbeat(0x47, '打包机心跳'),
  version(0x48, '版本查询'),
  resetFault(0x49, '故障复位'),
  paramRead(0x50, '参数读取'),
  paramWrite(0x51, '参数写入'),
  paramSave(0x52, '参数保存'),
  paramLoad(0x53, '参数加载');

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

const Map<int, String> kErrorCodeLabels = <int, String>{
  0x01: 'ERR_SEEKZERO_FAIL',
  0x02: 'ERR_MOTION_TIMEOUT',
  0x03: 'ERR_SENSOR_FAIL',
  0x04: 'ERR_MOTOR_STUCK',
  0x05: 'ERR_DOOR_FAIL',
  0x06: 'ERR_STATE_BUSY',
  0x07: 'ERR_COMM_TIMEOUT',
  0x11: 'ERR_M109_OVERCURRENT',
  0x12: 'ERR_M109_UNDERCURRENT',
  0x13: 'ERR_M109_TIMEOUT',
  0x14: 'ERR_M109_MOTOR_FAULT',
  0x15: 'ERR_M109_BAD_PARAMS',
  0x16: 'ERR_M109_SENSOR_FAULT',
  0x17: 'ERR_M109_DOOR_NOT_OPEN',
  0x21: 'ERR_PACKER_COMM_FAIL',
  0x22: 'ERR_PACKER_NO_TASK',
  0x23: 'ERR_BAG_TIMEOUT',
  0x24: 'ERR_M109_OFFLINE',
  0x25: 'ERR_M109_TRACK_ERR',
  0x26: 'ERR_FEED_TIMEOUT',
  0x27: 'ERR_STORE_OP_TIMEOUT',
  0x28: 'ERR_RES_OCCUPIED',
  0x29: 'ERR_QUERY_TIMEOUT',
  0x2A: 'ERR_UNLOCK_FAIL',
  0x2B: 'ERR_POS_CHECK_FAIL',
  0x2C: 'ERR_TEST_LOCKED',
  0x2D: 'ERR_INVALID_PARAM',
};

const Map<int, Set<int>> kRequestToExpectedResponseFunctions = <int, Set<int>>{
  0x01: <int>{0x01, 0x02, 0x0A},
  0x03: <int>{0x03, 0x04, 0x0A},
  0x05: <int>{0x05, 0x06, 0x0A},
  0x07: <int>{0x07, 0x08, 0x0A},
  0x09: <int>{0x09, 0x0A},
  0x0B: <int>{0x0B, 0x0A},
  0x0C: <int>{0x0C, 0x0D, 0x0A},
  0x10: <int>{0x10, 0x0A},
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
  0x50: <int>{0x50},
  0x51: <int>{0x51},
  0x52: <int>{0x52},
  0x53: <int>{0x53},
};

String toHex2(int value) =>
    value.toRadixString(16).padLeft(2, '0').toUpperCase();

String payloadToHex(List<int> data) => data.map(toHex2).join(' ');

String _yesNo(int value) => value == 0 ? '否' : '是';

String _packerResultName(int value) {
  return switch (value) {
    0x00 => 'OK',
    0x01 => 'INVALID_FUNC',
    0x02 => 'INVALID_PARAM',
    0x03 => 'BUSY',
    0x04 => 'REJECTED_STATE',
    0x05 => 'ALARM_ACTIVE',
    0x06 => 'HW_FAIL',
    0x07 => 'TIMEOUT',
    0x08 => 'UNSUPPORTED',
    _ => 'UNKNOWN_RESULT',
  };
}

String _avoidStateName(int value) {
  return switch (value) {
    0x00 => '无动作',
    0x01 => '缩进请求/动作中',
    0x02 => '推出请求/动作中',
    0x03 => '缩进完成',
    0x04 => '推出完成',
    _ => '未知',
  };
}

String _clearFlagName(int value) {
  return switch (value) {
    0x01 => '出袋完成',
    0x02 => '封口完成',
    0x03 => '投料完成',
    0x04 => '避让状态',
    _ => '未知标志',
  };
}

HmiDecodedFrame decodeHmiFrame(HmiFrame frame) {
  final d = frame.data;
  final raw = payloadToHex(d);

  switch (frame.function) {
    case 0x01:
      return HmiDecodedFrame(
        title: '订单接收响应(0x01)',
        summary: '订单/状态=${d[0]} 备用状态=${d[1]}',
        rawDataHex: raw,
      );
    case 0x03:
      return HmiDecodedFrame(
        title: '封口接收响应(0x03)',
        summary: '状态=${d[0]}',
        rawDataHex: raw,
      );
    case 0x05:
      return HmiDecodedFrame(
        title: '存放接收响应(0x05)',
        summary: '订单=${d[0]} 格号=${d[1]}',
        rawDataHex: raw,
      );
    case 0x07:
      return HmiDecodedFrame(
        title: '开锁接收响应(0x07)',
        summary: '订单=${d[0]} 格号=${d[1]}',
        rawDataHex: raw,
      );
    case 0x02:
      return HmiDecodedFrame(
        title: '投递状态反馈(0x02)',
        summary: '订单=${d[0]} 结果=${d[1]} 原因=${d[2]}',
        rawDataHex: raw,
      );
    case 0x04:
      return HmiDecodedFrame(
        title: '封口完成(0x04)',
        summary: '封口状态=0x${toHex2(d[0])}',
        rawDataHex: raw,
      );
    case 0x06:
      return HmiDecodedFrame(
        title: '存放反馈(0x06)',
        summary: '订单=${d[0]} 结果=${d[1]}',
        rawDataHex: raw,
      );
    case 0x08:
      final cabinetId = d[0] | (d[1] << 8);
      return HmiDecodedFrame(
        title: '开锁状态反馈(0x08)',
        summary: '格号=$cabinetId 开锁结果=${d[2]} 货物状态=${d[3]}',
        rawDataHex: raw,
      );
    case 0x09:
      final lockMask = (d[0] << 8) | d[1];
      final occupyMask = (d[2] << 8) | d[3];
      return HmiDecodedFrame(
        title: '状态查询响应(0x09)',
        summary:
            '锁状态=0x${lockMask.toRadixString(16).padLeft(4, '0').toUpperCase()} '
            '占用状态=0x${occupyMask.toRadixString(16).padLeft(4, '0').toUpperCase()}',
        rawDataHex: raw,
      );
    case 0x0A:
      final errorCode = d[0];
      final errorName = kErrorCodeLabels[errorCode] ?? 'UNKNOWN_ERROR';
      return HmiDecodedFrame(
        title: '错误上报(0x0A)',
        summary: '错误码=0x${toHex2(errorCode)} $errorName',
        rawDataHex: raw,
        errorCode: errorCode,
      );
    case 0x0B:
      return HmiDecodedFrame(
        title: '设备测试反馈(0x0B)',
        summary: '类型=${d[0]} 目标ID=${d[1] | (d[2] << 8)} 结果=${d[3]} 原因=${d[4]}',
        rawDataHex: raw,
      );
    case 0x0C:
      return HmiDecodedFrame(
        title: '退货接收响应(0x0C)',
        summary: '订单=${d[0]} 格号=${d[1]}',
        rawDataHex: raw,
      );
    case 0x0D:
      return HmiDecodedFrame(
        title: '退货反馈(0x0D)',
        summary: '订单=${d[0]} 格号=${d[1]} 有货=${d[2]} 门关=${d[3]}',
        rawDataHex: raw,
      );
    case 0x10:
      return HmiDecodedFrame(
        title: '初始化查询响应(0x10)',
        summary: '初始化标志=${d[0]}',
        rawDataHex: raw,
      );
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
            '结果=${_packerResultName(d[0])} 运行=${d[1]} 忙=${d[2]} 出袋=${d[3]} '
            '封口=${d[4]} 投料=${d[5]} 避让=${_avoidStateName(d[6])} '
            '报警=0x${toHex2(d[7])} flags=0x${toHex2(d[8])} 协议=${d[9]}',
        rawDataHex: raw,
      );
    case 0x42:
      return HmiDecodedFrame(
        title: '出袋触发响应(0x42)',
        summary:
            '结果=${_packerResultName(d[0])} 出袋状态=${d[1]} 报警=0x${toHex2(d[2])}',
        rawDataHex: raw,
      );
    case 0x43:
      return HmiDecodedFrame(
        title: '封口触发响应(0x43)',
        summary:
            '结果=${_packerResultName(d[0])} 封口状态=${d[1]} 报警=0x${toHex2(d[2])}',
        rawDataHex: raw,
      );
    case 0x44:
      return HmiDecodedFrame(
        title: '避让控制响应(0x44)',
        summary:
            '结果=${_packerResultName(d[0])} 避让=${_avoidStateName(d[1])} 报警=0x${toHex2(d[2])}',
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
        title: '打包机心跳(0x47)',
        summary:
            '结果=${_packerResultName(d[0])} 运行=${d[1]} 报警=0x${toHex2(d[2])} 协议=${d[3]}',
        rawDataHex: raw,
      );
    case 0x48:
      return HmiDecodedFrame(
        title: '打包机版本(0x48)',
        summary:
            '结果=${_packerResultName(d[0])} 协议=${d[1]}.${d[2]} '
            '固件=${d[3]}.${d[4]} 能力=0x${toHex2(d[5])}',
        rawDataHex: raw,
      );
    case 0x49:
      return HmiDecodedFrame(
        title: '故障复位响应(0x49)',
        summary: '结果=${_packerResultName(d[0])} 报警=0x${toHex2(d[1])}',
        rawDataHex: raw,
      );
    case 0x50:
      final paramId = d[1];
      final dataType = d[2];
      final value = d[3] | (d[4] << 8) | (d[5] << 16) | (d[6] << 24);
      return HmiDecodedFrame(
        title: '参数读取响应(0x50)',
        summary: '结果=${_packerResultName(d[0])} ID=0x${toHex2(paramId)} '
            '类型=$dataType 值=$value (0x${value.toRadixString(16)})',
        rawDataHex: raw,
      );
    case 0x51:
      final paramId = d[1];
      final value = d[2] | (d[3] << 8) | (d[4] << 16) | (d[5] << 24);
      return HmiDecodedFrame(
        title: '参数写入响应(0x51)',
        summary: '结果=${_packerResultName(d[0])} ID=0x${toHex2(paramId)} '
            '回读=$value',
        rawDataHex: raw,
      );
    case 0x52:
      return HmiDecodedFrame(
        title: '参数保存响应(0x52)',
        summary: '结果=${_packerResultName(d[0])}',
        rawDataHex: raw,
      );
    case 0x53:
      return HmiDecodedFrame(
        title: '参数加载响应(0x53)',
        summary: '结果=${_packerResultName(d[0])}',
        rawDataHex: raw,
      );
    default:
      return HmiDecodedFrame(
        title: '通用帧(0x${toHex2(frame.function)})',
        summary:
            'ADDR=0x${toHex2(frame.address)} FUNC=0x${toHex2(frame.function)}',
        rawDataHex: raw,
      );
  }
}
