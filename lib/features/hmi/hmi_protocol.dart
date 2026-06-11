import '../../core/protocol/hmi_frame.dart';
import 'hmi_hmis_bam.dart';
import 'hmi_session_frame.dart';
import 'hmi_session_single_frame.dart';

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
  dcMotor2Jog(0x4C, '直流2点动'),
  relayJog(0x4D, '继电器点动');

  const HmiPackerFunction(this.code, this.label);
  final int code;
  final String label;
}

class HmiRetryPolicy {
  const HmiRetryPolicy({
    this.maxRetries = 1,
    this.timeoutMs = 8000,
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

String _bamControlIndexName(int value) {
  return switch (value) {
    hmisBamFragIndexAck => 'ACK',
    hmisBamFragIndexNack => 'NACK',
    _ => 'DATA',
  };
}

HmiDecodedFrame _decodeHmisBamFrame(HmiFrame frame) {
  final d = frame.data;
  final raw = payloadToHex(d);
  final tid = HmisBamFrameBuilder.readTransactionId(d);
  final fragIndex = d[4];
  final fragCount = d[5];
  final fragLength = d[6];
  final reserved = d[15];
  final reservedText = reserved == 0
      ? 'reserved=00'
      : 'reserved=0x${toHex2(reserved)}(非法)';

  if (fragIndex == hmisBamFragIndexAck || fragIndex == hmisBamFragIndexNack) {
    final status =
        HmisBamControlStatus.tryParse(d[8])?.name.toUpperCase() ??
        'UNKNOWN(0x${toHex2(d[8])})';
    return HmiDecodedFrame(
      title: 'HMIS-BAM ${_bamControlIndexName(fragIndex)}',
      summary:
          'tid=$tid frag=${toHex2(d[7])} status=$status next=${toHex2(d[9])} $reservedText',
      rawDataHex: raw,
    );
  }

  final payloadEnd =
      7 +
      (fragLength > hmisBamFragmentPayloadSize
          ? hmisBamFragmentPayloadSize
          : fragLength);
  return HmiDecodedFrame(
    title: 'HMIS-BAM DATA',
    summary:
        'tid=$tid frag=$fragIndex/$fragCount len=$fragLength payload=${payloadToHex(d.sublist(7, payloadEnd))} $reservedText',
    rawDataHex: raw,
  );
}

HmiDecodedFrame _decodeHmiSessionSingleFrame(HmiFrame frame) {
  final d = frame.data;
  final raw = payloadToHex(d);
  final type =
      HmiSessionFrameType.tryParse(d[0])?.name.toUpperCase() ??
      'UNKNOWN(0x${toHex2(d[0])})';
  final sequence = d[1] | (d[2] << 8);
  final command =
      HmiSessionCommand.tryParse(d[3])?.name ?? 'UNKNOWN(0x${toHex2(d[3])})';
  final length = d[5];
  final payloadEnd =
      6 +
      (length > hmiSessionSingleFramePayloadSize
          ? hmiSessionSingleFramePayloadSize
          : length);
  final invalid = length > hmiSessionSingleFramePayloadSize ? ' 非法LEN' : '';
  return HmiDecodedFrame(
    title: 'HMI Session SINGLE(0x7E)',
    summary:
        'type=$type seq=$sequence cmd=$command flags=0x${toHex2(d[4])} len=$length payload=${payloadToHex(d.sublist(6, payloadEnd))}$invalid',
    rawDataHex: raw,
  );
}

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

String _actionName(int value) {
  return switch (value) {
    0 => '停机',
    1 => '启动',
    2 => '完成查询',
    _ => '未知($value)',
  };
}

String _scopeName(int value) {
  return switch (value) {
    0 => '清除报警码',
    1 => '清除锁存',
    2 => '全部复位+停机',
    _ => '未知($value)',
  };
}

/// 解码发送帧（Y 分区：请求参数）。
HmiDecodedFrame decodeHmiFrameTx(HmiFrame frame) {
  final d = frame.data;
  final raw = payloadToHex(d);

  switch (frame.function) {
    case 0x40:
      return HmiDecodedFrame(
        title: '打包机启停请求(0x40)',
        summary: 'Y1=操作:${_actionName(d[0])}',
        rawDataHex: raw,
      );
    case 0x41:
      return HmiDecodedFrame(
        title: '打包机状态查询(0x41)',
        summary: 'Y1~Y16=0 (查询)',
        rawDataHex: raw,
      );
    case 0x42:
      return HmiDecodedFrame(
        title: '出袋触发请求(0x42)',
        summary: 'Y1=操作:${_actionName(d[0])} Y2=清除标志:${d[1] == 0 ? "是" : "否"}',
        rawDataHex: raw,
      );
    case 0x43:
      return HmiDecodedFrame(
        title: '封口触发请求(0x43)',
        summary: 'Y1=操作:${_actionName(d[0])} Y2=清除标志:${d[1] == 0 ? "是" : "否"}',
        rawDataHex: raw,
      );
    case 0x44:
      return HmiDecodedFrame(
        title: '投料触发请求(0x44)',
        summary: 'Y1=操作:${_actionName(d[0])} Y2=清除标志:${d[1] == 0 ? "是" : "否"}',
        rawDataHex: raw,
      );
    case 0x45:
      return HmiDecodedFrame(
        title: '清除标志请求(0x45)',
        summary: 'Y1=标志:${_clearFlagName(d[0])}',
        rawDataHex: raw,
      );
    case 0x46:
      return HmiDecodedFrame(
        title: '报警查询请求(0x46)',
        summary: 'Y1~Y16=0 (查询)',
        rawDataHex: raw,
      );
    case 0x47:
      return HmiDecodedFrame(
        title: '打印机透传请求(0x47)',
        summary: 'Y1=打印机命令:0x${toHex2(d[0])}',
        rawDataHex: raw,
      );
    case 0x48:
      return HmiDecodedFrame(
        title: '版本查询请求(0x48)',
        summary: 'Y1~Y16=0 (查询)',
        rawDataHex: raw,
      );
    case 0x49:
      return HmiDecodedFrame(
        title: '故障复位请求(0x49)',
        summary: 'Y1=范围:${_scopeName(d[0])}',
        rawDataHex: raw,
      );
    case 0x4A:
      return HmiDecodedFrame(
        title: '步进点动请求(0x4A)',
        summary:
            'Y1=电机:${d[0]} Y2=方向:${d[1] == 0 ? "正转" : "反转"} '
            'Y3~Y4=脉冲:${(d[2] << 8) | d[3]}',
        rawDataHex: raw,
      );
    case 0x4B:
      return HmiDecodedFrame(
        title: '直流1点动请求(0x4B)',
        summary:
            'Y1=方向:${d[0] == 0 ? "正转" : "反转"} '
            'Y2~Y3=时长:${(d[1] << 8) | d[2]}ms',
        rawDataHex: raw,
      );
    case 0x4C:
      return HmiDecodedFrame(
        title: '直流2点动请求(0x4C)',
        summary:
            'Y1=方向:${d[0] == 0 ? "正转" : "反转"} '
            'Y2~Y3=时长:${(d[1] << 8) | d[2]}ms',
        rawDataHex: raw,
      );
    default:
      return HmiDecodedFrame(
        title: '未知请求(0x${toHex2(frame.function)})',
        summary: '原始数据: $raw',
        rawDataHex: raw,
      );
  }
}

/// 解码接收帧（Z 分区：响应参数）。
HmiDecodedFrame decodeHmiFrameRx(HmiFrame frame) {
  final d = frame.data;
  final raw = payloadToHex(d);

  switch (frame.function) {
    case 0x40:
      return HmiDecodedFrame(
        title: '打包机启停响应(0x40)',
        summary:
            'Z1=结果:${_packerResultName(d[0])} Z2=运行:${d[1]} Z3=报警:0x${toHex2(d[2])}',
        rawDataHex: raw,
      );
    case 0x41:
      return HmiDecodedFrame(
        title: '打包机状态响应(0x41)',
        summary:
            'Z1=结果:${_packerResultName(d[0])} Z2=运行:${d[1]} Z4=busy:0x${toHex2(d[3])} '
            'Z5=出袋:${d[4]} Z6=封口:${d[5]} Z7=投料:${d[6]} Z11=报警:0x${toHex2(d[10])}',
        rawDataHex: raw,
      );
    case 0x42:
      return HmiDecodedFrame(
        title: '出袋触发响应(0x42)',
        summary:
            'Z1=结果:${_packerResultName(d[0])} Z2=锁存:${d[1]} Z3=报警:0x${toHex2(d[2])}',
        rawDataHex: raw,
      );
    case 0x43:
      return HmiDecodedFrame(
        title: '封口触发响应(0x43)',
        summary:
            'Z1=结果:${_packerResultName(d[0])} Z2=锁存:${d[1]} Z3=报警:0x${toHex2(d[2])}',
        rawDataHex: raw,
      );
    case 0x44:
      return HmiDecodedFrame(
        title: '投料触发响应(0x44)',
        summary:
            'Z1=结果:${_packerResultName(d[0])} Z2=锁存:${d[1]} Z3=报警:0x${toHex2(d[2])}',
        rawDataHex: raw,
      );
    case 0x45:
      return HmiDecodedFrame(
        title: '清除标志响应(0x45)',
        summary:
            'Z1=结果:${_packerResultName(d[0])} Z2=标志:${_clearFlagName(d[1])}',
        rawDataHex: raw,
      );
    case 0x46:
      return HmiDecodedFrame(
        title: '报警查询响应(0x46)',
        summary:
            'Z1=结果:${_packerResultName(d[0])} Z2=报警:0x${toHex2(d[1])} Z3=锁存:${_yesNo(d[2])}',
        rawDataHex: raw,
      );
    case 0x47:
      return HmiDecodedFrame(
        title: '打印机透传响应(0x47)',
        summary:
            'Z1=结果:${_packerResultName(d[0])} Z2=rsp_cmd:0x${toHex2(d[1])} Z3=len:${d[2]}',
        rawDataHex: raw,
      );
    case 0x48:
      return HmiDecodedFrame(
        title: '版本查询响应(0x48)',
        summary:
            'Z1=结果:${_packerResultName(d[0])} Z2~Z3=ver:${d[1]}.${d[2]} Z4=cap:0x${toHex2(d[3])}',
        rawDataHex: raw,
      );
    case 0x49:
      return HmiDecodedFrame(
        title: '故障复位响应(0x49)',
        summary:
            'Z1=结果:${_packerResultName(d[0])} Z2=报警:0x${toHex2(d[1])} Z3=锁存:${_yesNo(d[2])}',
        rawDataHex: raw,
      );
    case 0x4A:
      return HmiDecodedFrame(
        title: '步进点动响应(0x4A)',
        summary:
            'Z1=结果:${_packerResultName(d[0])} Z2=电机:${d[1]} Z3=方向:${d[2]} '
            'Z4~Z5=脉冲:${(d[3] << 8) | d[4]}',
        rawDataHex: raw,
      );
    case 0x4B:
      return HmiDecodedFrame(
        title: '直流1点动响应(0x4B)',
        summary:
            'Z1=结果:${_packerResultName(d[0])} Z2=电机:${d[1]} Z3=方向:${d[2]} '
            'Z4~Z5=时长:${(d[3] << 8) | d[4]}ms',
        rawDataHex: raw,
      );
    case 0x4C:
      return HmiDecodedFrame(
        title: '直流2点动响应(0x4C)',
        summary:
            'Z1=结果:${_packerResultName(d[0])} Z2=电机:${d[1]} Z3=方向:${d[2]} '
            'Z4~Z5=时长:${(d[3] << 8) | d[4]}ms',
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

/// 根据方向自动选择 Y（发送）或 Z（接收）解码。
HmiDecodedFrame decodeHmiFrame(HmiFrame frame, {String direction = 'RX'}) {
  if (frame.function == hmiSessionSingleFrameFunction) {
    return _decodeHmiSessionSingleFrame(frame);
  }
  if (frame.function == hmisBamFunction) {
    return _decodeHmisBamFrame(frame);
  }
  return direction == 'TX' ? decodeHmiFrameTx(frame) : decodeHmiFrameRx(frame);
}
