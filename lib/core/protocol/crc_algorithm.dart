/// CRC16 算法枚举。
///
/// 支持可配置的 CRC16 算法，当前包含 Modbus 和 DBUS 两种变体。
/// 后续可按需扩展多项式与参数。
enum CrcAlgorithm {
  /// CRC16-Modbus
  ///
  /// - 多项式：`0x8005`（反转 `0xA001`）
  /// - 初始值：`0xFFFF`
  /// - 输入反转：是
  /// - 输出反转：是
  /// - 结果异或：`0x0000`
  modbus(0xA001, 0xFFFF, 0x0000),

  /// CRC16-DBUS（CRC-16/IBM 变体）
  ///
  /// - 多项式：`0x8005`（反转 `0xA001`）
  /// - 初始值：`0x0000`
  /// - 输入反转：是
  /// - 输出反转：是
  /// - 结果异或：`0x0000`
  dbus(0xA001, 0x0000, 0x0000);

  const CrcAlgorithm(this.polyReflected, this.init, this.xorOut);

  /// 反转后的多项式（低位优先）。
  final int polyReflected;

  /// CRC 初始值。
  final int init;

  /// 结果异或值。
  final int xorOut;

  /// 计算字节序列的 CRC16 校验值。
  ///
  /// 所有变体均使用反转查表算法，输入输出均为低位优先。
  /// 序列化时按低字节在前写入帧尾。
  int compute(Iterable<int> bytes) {
    var crc = init;
    for (final value in bytes) {
      crc ^= value & 0xFF;
      for (var bit = 0; bit < 8; bit++) {
        if ((crc & 0x0001) != 0) {
          crc = (crc >> 1) ^ polyReflected;
        } else {
          crc >>= 1;
        }
      }
    }
    return (crc & 0xFFFF) ^ xorOut;
  }

  /// 从字符串名称解析算法枚举。
  ///
  /// 不区分大小写，支持 `"modbus"`、`"dbus"`。
  /// 无法解析时返回 `null`。
  static CrcAlgorithm? tryParse(String name) {
    return switch (name.trim().toLowerCase()) {
      'modbus' => CrcAlgorithm.modbus,
      'dbus' => CrcAlgorithm.dbus,
      _ => null,
    };
  }

  /// 友好显示名称。
  String get displayName {
    return switch (this) {
      CrcAlgorithm.modbus => 'CRC16-Modbus',
      CrcAlgorithm.dbus => 'CRC16-DBUS',
    };
  }
}
