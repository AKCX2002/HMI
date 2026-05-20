import 'dart:io' show Directory, File, Platform;

/// 原生平台（Linux/Windows/macOS/Android）日志导出：写入文件。
/// 成功返回文件路径；失败抛出异常，由调用方处理回退。
Future<String?> exportLogsToFile(String content) async {
  final dir = Directory(
    Platform.isAndroid
        ? '/storage/emulated/0/Download'
        : (Platform.environment['HOME'] ?? '.'),
  );
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final timestamp = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');
  final file = File('${dir.path}/hmi_log_$timestamp.txt');
  await file.writeAsString(content);
  return file.path;
}
