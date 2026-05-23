const List<String> kKnownStackTaskNames = <String>[
  'ProtoTask',
  'StateMachineTask',
  'MotorTask',
  'AdcTask',
  'CommTask',
  'MonitorTask',
  'HeaterTask',
];

class StackTaskSnapshot {
  const StackTaskSnapshot({
    required this.name,
    required this.totalWords,
    required this.freeWords,
    required this.usedWords,
    required this.usedRatio,
    required this.timestamp,
  });

  final String name;
  final int totalWords;
  final int freeWords;
  final int usedWords;
  final double usedRatio;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'total_words': totalWords,
    'free_words': freeWords,
    'used_words': usedWords,
    'used_ratio': usedRatio,
    'ts': timestamp.toIso8601String(),
  };
}

class StackSummarySnapshot {
  const StackSummarySnapshot({
    required this.totalWords,
    required this.totalFreeWords,
    required this.totalUsedWords,
    required this.riskiestTaskName,
  });

  final int totalWords;
  final int totalFreeWords;
  final int totalUsedWords;
  final String riskiestTaskName;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'total_words': totalWords,
    'total_free_words': totalFreeWords,
    'total_used_words': totalUsedWords,
    'riskiest_task_name': riskiestTaskName,
  };
}

class StackSnapshot {
  const StackSnapshot({
    required this.timestamp,
    required this.tasks,
    required this.summary,
  });

  final DateTime timestamp;
  final List<StackTaskSnapshot> tasks;
  final StackSummarySnapshot summary;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'ts': timestamp.toIso8601String(),
    'summary': summary.toJson(),
    'tasks': tasks.map((task) => task.toJson()).toList(),
  };
}

class StackTaskStats {
  const StackTaskStats({
    required this.name,
    required this.totalWords,
    required this.freeWords,
    required this.usedWords,
    required this.usedRatio,
    required this.minFreeWords,
    required this.maxUsedWords,
    required this.updatedAt,
  });

  final String name;
  final int totalWords;
  final int freeWords;
  final int usedWords;
  final double usedRatio;
  final int minFreeWords;
  final int maxUsedWords;
  final DateTime updatedAt;

  StackTaskStats merge(StackTaskSnapshot snapshot) {
    return StackTaskStats(
      name: name,
      totalWords: snapshot.totalWords,
      freeWords: snapshot.freeWords,
      usedWords: snapshot.usedWords,
      usedRatio: snapshot.usedRatio,
      minFreeWords: minFreeWords < snapshot.freeWords
          ? minFreeWords
          : snapshot.freeWords,
      maxUsedWords: maxUsedWords > snapshot.usedWords
          ? maxUsedWords
          : snapshot.usedWords,
      updatedAt: snapshot.timestamp,
    );
  }

  factory StackTaskStats.fromSnapshot(StackTaskSnapshot snapshot) {
    return StackTaskStats(
      name: snapshot.name,
      totalWords: snapshot.totalWords,
      freeWords: snapshot.freeWords,
      usedWords: snapshot.usedWords,
      usedRatio: snapshot.usedRatio,
      minFreeWords: snapshot.freeWords,
      maxUsedWords: snapshot.usedWords,
      updatedAt: snapshot.timestamp,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'total_words': totalWords,
    'free_words': freeWords,
    'used_words': usedWords,
    'used_ratio': usedRatio,
    'min_free_words': minFreeWords,
    'max_used_words': maxUsedWords,
    'updated_at': updatedAt.toIso8601String(),
  };
}

class StackStatsCollector {
  StackStatsCollector({this.maxBufferedLines = 24});

  final int maxBufferedLines;
  final Map<String, _StackTaskRecord> _records = <String, _StackTaskRecord>{};
  bool _isCollecting = false;
  int _bufferedLineCount = 0;

  bool get isCollecting => _isCollecting;
  int get bufferedLineCount => _bufferedLineCount;

  StackSnapshot? addLogLine(String text, {DateTime? timestamp}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    if (trimmed == 'STACK_SNAPSHOT_BEGIN') {
      _resetState();
      _isCollecting = true;
      return null;
    }

    if (!_isCollecting) {
      return null;
    }

    if (trimmed == 'STACK_SNAPSHOT_END') {
      final snapshot = _buildSnapshot(timestamp ?? DateTime.now());
      _resetState();
      return snapshot;
    }

    _bufferedLineCount++;
    if (_bufferedLineCount > maxBufferedLines) {
      _resetState();
      return null;
    }

    final taskMatch = RegExp(
      r'^STACK_TASK\s+NAME=([A-Za-z0-9_]+)\s+TOTAL=(\d+)\s+FREE=(\d+)$',
    ).firstMatch(trimmed);
    if (taskMatch == null) {
      return null;
    }

    final name = taskMatch.group(1) ?? '';
    if (!kKnownStackTaskNames.contains(name)) {
      return null;
    }

    final totalWords = int.tryParse(taskMatch.group(2) ?? '');
    final freeWords = int.tryParse(taskMatch.group(3) ?? '');
    if (totalWords == null || freeWords == null || totalWords <= 0) {
      return null;
    }

    _records[name] = _StackTaskRecord(
      name: name,
      totalWords: totalWords,
      freeWords: freeWords,
    );
    return null;
  }

  void reset() {
    _resetState();
  }

  void _resetState() {
    _records.clear();
    _bufferedLineCount = 0;
    _isCollecting = false;
  }

  StackSnapshot? _buildSnapshot(DateTime timestamp) {
    if (_records.length != kKnownStackTaskNames.length) {
      return null;
    }

    final List<StackTaskSnapshot> tasks = <StackTaskSnapshot>[];
    for (final name in kKnownStackTaskNames) {
      final record = _records[name];
      if (record == null) {
        return null;
      }
      final usedWords = record.totalWords - record.freeWords;
      final usedRatio = record.totalWords == 0
          ? 0.0
          : usedWords / record.totalWords;
      tasks.add(
        StackTaskSnapshot(
          name: name,
          totalWords: record.totalWords,
          freeWords: record.freeWords,
          usedWords: usedWords,
          usedRatio: usedRatio,
          timestamp: timestamp,
        ),
      );
    }

    final totalWords = tasks.fold<int>(0, (sum, task) => sum + task.totalWords);
    final totalFreeWords = tasks.fold<int>(
      0,
      (sum, task) => sum + task.freeWords,
    );
    final totalUsedWords = totalWords - totalFreeWords;
    tasks.sort((a, b) {
      final freeCompare = a.freeWords.compareTo(b.freeWords);
      if (freeCompare != 0) {
        return freeCompare;
      }
      return b.usedRatio.compareTo(a.usedRatio);
    });
    final riskiestTaskName = tasks.first.name;

    final orderedTasks = <StackTaskSnapshot>[
      for (final name in kKnownStackTaskNames)
        tasks.firstWhere((task) => task.name == name),
    ];

    return StackSnapshot(
      timestamp: timestamp,
      tasks: orderedTasks,
      summary: StackSummarySnapshot(
        totalWords: totalWords,
        totalFreeWords: totalFreeWords,
        totalUsedWords: totalUsedWords,
        riskiestTaskName: riskiestTaskName,
      ),
    );
  }
}

Map<String, StackTaskStats> mergeStackTaskStats(
  Map<String, StackTaskStats> current,
  StackSnapshot snapshot,
) {
  final Map<String, StackTaskStats> next = <String, StackTaskStats>{};
  for (final task in snapshot.tasks) {
    final existing = current[task.name];
    next[task.name] = existing == null
        ? StackTaskStats.fromSnapshot(task)
        : existing.merge(task);
  }
  return next;
}

class _StackTaskRecord {
  const _StackTaskRecord({
    required this.name,
    required this.totalWords,
    required this.freeWords,
  });

  final String name;
  final int totalWords;
  final int freeWords;
}
