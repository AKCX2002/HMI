void _ignoreArg(Object? value) {
  final _ = value;
}

/// Web 平台日志导出：不支持文件系统，抛出 UnsupportedError 由调用方回退到剪贴板。
Future<String> exportLogsToFile(String content) async {
  throw UnsupportedError('Web 平台不支持文件系统导出');
}

class LogExportCancelledException implements Exception {
  const LogExportCancelledException();
}

class LogBundleTextFile {
  const LogBundleTextFile({required this.name, required this.content});

  final String name;
  final String content;
}

class LogBundleSourceFile {
  const LogBundleSourceFile({required this.archiveName, required this.path});

  final String archiveName;
  final String path;
}

Future<String> exportLogBundle({
  required String bundleBaseName,
  List<LogBundleTextFile> textFiles = const <LogBundleTextFile>[],
  List<LogBundleSourceFile> sourceFiles = const <LogBundleSourceFile>[],
  Future<String?> Function(String suggestedName)? saveLocationPicker,
}) async {
  _ignoreArg(bundleBaseName);
  _ignoreArg(textFiles);
  _ignoreArg(sourceFiles);
  _ignoreArg(saveLocationPicker);
  throw UnsupportedError('Web 平台不支持日志打包导出');
}

Future<String> appendLogsChunk(
  String content, {
  String? existingPath,
  String filePrefix = 'hmi_live_log',
  Future<String> Function()? autoLogDirResolver,
}) async {
  _ignoreArg(content);
  _ignoreArg(existingPath);
  _ignoreArg(filePrefix);
  _ignoreArg(autoLogDirResolver);
  throw UnsupportedError('Web 平台不支持文件系统自动落盘');
}
