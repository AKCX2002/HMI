/// Web 平台日志导出：直接回退到剪贴板，返回 null。
Future<String?> exportLogsToFile(String content) async {
  return null; // Web 不支持文件系统写入，调用方应回退到剪贴板
}
