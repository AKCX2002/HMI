import 'dart:io' show Directory, File, FileMode, Platform;

const int _maxRollingLogBytes = 32 * 1024 * 1024;

String _timestampForFileName() => DateTime.now()
    .toIso8601String()
    .replaceAll(':', '-')
    .replaceAll('.', '-');

/// 原生平台（Linux/Windows/macOS/Android）日志导出：写入文件。
/// 成功返回文件路径；失败抛出异常，由调用方处理回退。
Future<String> exportLogsToFile(String content) async {
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

/// 自动落盘：将日志块追加到同一滚动日志文件。
///
/// - [content] 为空时直接返回已有路径或空字符串
/// - [existingPath] 可传上次路径，确保同一会话持续追加
Future<String> appendLogsChunk(
  String content, {
  String? existingPath,
}) async {
  if (content.isEmpty) {
    return existingPath ?? '';
  }
  final dir = Directory(
    Platform.isAndroid
        ? '/storage/emulated/0/Download'
        : (Platform.environment['HOME'] ?? '.'),
  );
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }

  final path = (existingPath != null && existingPath.isNotEmpty)
      ? existingPath
      : '${dir.path}/hmi_live_log_${_timestampForFileName()}.jsonl';

  var file = File(path);
  if (await file.exists()) {
    final len = await file.length();
    if (len >= _maxRollingLogBytes) {
      file = File('${dir.path}/hmi_live_log_${_timestampForFileName()}.jsonl');
    }
  }

  await file.writeAsString(content, mode: FileMode.append, flush: true);
  return file.path;
}
