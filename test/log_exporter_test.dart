import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hmi_host/util/log_exporter.dart';

void main() {
  test('appendLogsChunk 写入解析后的自动落盘目录', () async {
    final tempDir = await Directory.systemTemp.createTemp('hmi_log_dir_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final path = await appendLogsChunk(
      '{"msg":"hello"}\n',
      filePrefix: 'session_log',
      autoLogDirResolver: () async => tempDir.path,
    );

    final file = File(path);
    expect(await file.exists(), isTrue);
    expect(file.path, startsWith(tempDir.path));
    expect(await file.readAsString(), '{"msg":"hello"}\n');
  });

  test('exportLogBundle 生成包含文本与历史日志文件的 zip', () async {
    final tempDir = await Directory.systemTemp.createTemp('hmi_bundle_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final rollingFile = File('${tempDir.path}/hmi_live_log.jsonl');
    await rollingFile.writeAsString('{"line":"A"}\n{"line":"B"}\n');
    final savePath = '${tempDir.path}/full_logs.zip';

    final bundlePath = await exportLogBundle(
      bundleBaseName: 'full_logs',
      textFiles: const <LogBundleTextFile>[
        LogBundleTextFile(
          name: 'protocol_logs.txt',
          content: 'ALL LOGS\nentry-1\nentry-2\n',
        ),
      ],
      sourceFiles: <LogBundleSourceFile>[
        LogBundleSourceFile(
          archiveName: 'raw/hmi_live_log.jsonl',
          path: rollingFile.path,
        ),
      ],
      saveLocationPicker: (_) async => savePath,
    );

    expect(bundlePath, savePath);

    final bytes = await File(bundlePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.files.map((file) => file.name).toSet();
    expect(names, contains('protocol_logs.txt'));
    expect(names, contains('raw/hmi_live_log.jsonl'));

    final textFile = archive.files.firstWhere(
      (file) => file.name == 'protocol_logs.txt',
    );
    expect(
      utf8.decode(textFile.content as List<int>),
      'ALL LOGS\nentry-1\nentry-2\n',
    );

    final rawFile = archive.files.firstWhere(
      (file) => file.name == 'raw/hmi_live_log.jsonl',
    );
    expect(
      utf8.decode(rawFile.content as List<int>),
      '{"line":"A"}\n{"line":"B"}\n',
    );
  });
}
