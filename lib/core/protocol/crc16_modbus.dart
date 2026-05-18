/// 计算字节序列的 CRC16-Modbus。
///
/// 约定：
/// - 多项式：`0xA001`（`0x8005` 反转）
/// - 初始值：`0xFFFF`
/// - 结果范围：`0x0000..0xFFFF`
/// - 序列化时按低字节在前写入帧尾
int crc16Modbus(Iterable<int> bytes) {
  var crc = 0xFFFF;
  for (final value in bytes) {
    crc ^= value & 0xFF;
    for (var bit = 0; bit < 8; bit++) {
      if ((crc & 0x0001) != 0) {
        crc = (crc >> 1) ^ 0xA001;
      } else {
        crc >>= 1;
      }
    }
  }
  return crc & 0xFFFF;
}
