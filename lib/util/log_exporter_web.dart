/// Web 平台日志导出：不支持文件系统，抛出 UnsupportedError 由调用方回退到剪贴板。
Future<String> exportLogsToFile(String content) async {
  throw UnsupportedError('Web 平台不支持文件系统导出');
}

Future<String> appendLogsChunk(
  String content, {
  String? existingPath,
}) async {
  throw UnsupportedError('Web 平台不支持文件系统自动落盘');
}
