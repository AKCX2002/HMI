import 'dart:typed_data';

import 'crc_algorithm.dart';

/// 将原始负载归一化为固定 16 字节列表。
Uint8List _normalizeData(List<int>? data) {
  final payload = data ?? const <int>[];
  final frameData = List<int>.filled(16, 0);
  final copyLength = payload.length > 16 ? 16 : payload.length;
  frameData.setRange(0, copyLength, payload);
  return Uint8List.fromList(frameData);
}

/// UART3 应用协议帧。
///
/// 帧结构：
/// - byte[0] `address`
/// - byte[1] `function`
/// - byte[2..17] `data`（16 字节，不足补 0）
/// - byte[18..19] `CRC16`（低字节在前）
///
/// CRC 算法可通过 [crcAlgorithm] 参数配置，默认使用 CRC16-Modbus。
class HmiFrame {
  /// 创建协议帧，并将负载归一化为固定 16 字节。
  ///
  /// [crcAlgorithm] 指定编码时使用的 CRC 算法，默认 Modbus。
  HmiFrame({
    required this.address,
    required this.function,
    List<int>? data,
    this.crcAlgorithm = CrcAlgorithm.modbus,
  }) : data = _normalizeData(data);

  /// 协议地址，常见为 `0xAF` 请求 / `0xBF` 响应。
  final int address;

  /// 协议功能码（func）。
  final int function;

  /// 固定 16 字节数据域。
  final Uint8List data;

  /// 此帧使用的 CRC 算法。
  final CrcAlgorithm crcAlgorithm;

  /// 单帧总长度（字节）。
  static const int frameLength = 20;

  /// 上位机到设备地址。
  static const int appRequestAddress = 0xAF;

  /// 设备到上位机地址。
  static const int appResponseAddress = 0xBF;

  /// 将对象编码为 20 字节传输帧。
  Uint8List encode() {
    final frame = Uint8List(frameLength);
    frame[0] = address & 0xFF;
    frame[1] = function & 0xFF;
    frame.setRange(2, 18, data);
    final crc = crcAlgorithm.compute(frame.sublist(0, 18));
    frame[18] = crc & 0xFF;
    frame[19] = (crc >> 8) & 0xFF;
    return frame;
  }

  /// 尝试使用指定算法解码完整帧。
  ///
  /// [crcAlgorithm] 指定校验时使用的 CRC 算法；默认 Modbus。
  /// 当长度或 CRC 校验失败时返回 `null`。
  static HmiFrame? tryDecode(
    List<int> bytes, {
    CrcAlgorithm crcAlgorithm = CrcAlgorithm.modbus,
  }) {
    if (bytes.length != frameLength) {
      return null;
    }
    final receivedCrc = (bytes[19] << 8) | bytes[18];
    final calcCrc = crcAlgorithm.compute(bytes.sublist(0, 18));
    if (receivedCrc != calcCrc) {
      return null;
    }
    return HmiFrame(
      address: bytes[0],
      function: bytes[1],
      data: bytes.sublist(2, 18),
      crcAlgorithm: crcAlgorithm,
    );
  }
}
