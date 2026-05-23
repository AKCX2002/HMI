import 'dart:convert';
import 'dart:io' show Directory, File, FileMode, Platform;

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

const int _maxRollingLogBytes = 32 * 1024 * 1024;

String _timestampForFileName() =>
    DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');

class LogExportCancelledException implements Exception {
  const LogExportCancelledException();

  @override
  String toString() => '日志导出已取消';
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

typedef AutoLogDirResolver = Future<String> Function();
typedef SaveLocationPicker = Future<String?> Function(String suggestedName);

Future<String> _defaultAutoLogDirPath() async {
  if (Platform.isAndroid) {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  return Platform.environment['HOME'] ?? '.';
}

Future<String?> _defaultSaveLocationPicker(String suggestedName) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: const <XTypeGroup>[
      XTypeGroup(label: 'ZIP archives', extensions: <String>['zip']),
      XTypeGroup(label: 'Text files', extensions: <String>['txt']),
    ],
  );
  return location?.path;
}

/// 原生平台（Linux/Windows/macOS/Android）日志导出：写入文件。
/// 成功返回文件路径；失败抛出异常，由调用方处理回退。
Future<String> exportLogsToFile(String content) async {
  final dir = Directory(await _defaultAutoLogDirPath());
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

Future<String> exportLogBundle({
  required String bundleBaseName,
  List<LogBundleTextFile> textFiles = const <LogBundleTextFile>[],
  List<LogBundleSourceFile> sourceFiles = const <LogBundleSourceFile>[],
  SaveLocationPicker? saveLocationPicker,
}) async {
  final picker = saveLocationPicker ?? _defaultSaveLocationPicker;
  final suggestedName = '${bundleBaseName}_${_timestampForFileName()}.zip';
  final selectedPath = await picker(suggestedName);
  if (selectedPath == null || selectedPath.isEmpty) {
    throw const LogExportCancelledException();
  }

  final archive = Archive();
  for (final file in textFiles) {
    final bytes = utf8.encode(file.content);
    archive.addFile(ArchiveFile.bytes(file.name, bytes));
  }

  for (final file in sourceFiles) {
    final bytes = await File(file.path).readAsBytes();
    archive.addFile(ArchiveFile.bytes(file.archiveName, bytes));
  }

  final zipBytes = ZipEncoder().encode(archive);

  final outFile = File(selectedPath);
  final parent = outFile.parent;
  if (!await parent.exists()) {
    await parent.create(recursive: true);
  }
  await outFile.writeAsBytes(zipBytes, flush: true);
  return outFile.path;
}

/// 自动落盘：将日志块追加到同一滚动日志文件。
///
/// - [content] 为空时直接返回已有路径或空字符串
/// - [existingPath] 可传上次路径，确保同一会话持续追加
Future<String> appendLogsChunk(
  String content, {
  String? existingPath,
  String filePrefix = 'hmi_live_log',
  AutoLogDirResolver? autoLogDirResolver,
}) async {
  if (content.isEmpty) {
    return existingPath ?? '';
  }
  final dirPath = await (autoLogDirResolver ?? _defaultAutoLogDirPath)();
  final dir = Directory(dirPath);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }

  final path = (existingPath != null && existingPath.isNotEmpty)
      ? existingPath
      : '${dir.path}/${filePrefix}_${_timestampForFileName()}.jsonl';

  var file = File(path);
  if (await file.exists()) {
    final len = await file.length();
    if (len >= _maxRollingLogBytes) {
      file = File('${dir.path}/${filePrefix}_${_timestampForFileName()}.jsonl');
    }
  }

  await file.writeAsString(content, mode: FileMode.append, flush: true);
  return file.path;
}
