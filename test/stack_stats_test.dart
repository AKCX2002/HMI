import 'package:flutter_test/flutter_test.dart';
import 'package:hmi_host/features/hmi/stack_stats.dart';

void main() {
  group('StackStatsCollector', () {
    test('完整快照可解析并聚合总览', () {
      final collector = StackStatsCollector();
      final now = DateTime(2026, 5, 23, 12, 0, 0);

      expect(
        collector.addLogLine('STACK_SNAPSHOT_BEGIN', timestamp: now),
        isNull,
      );
      expect(
        collector.addLogLine(
          'STACK_TASK NAME=ProtoTask TOTAL=384 FREE=320',
          timestamp: now,
        ),
        isNull,
      );
      expect(
        collector.addLogLine(
          'STACK_TASK NAME=StateMachineTask TOTAL=576 FREE=400',
          timestamp: now,
        ),
        isNull,
      );
      expect(
        collector.addLogLine(
          'STACK_TASK NAME=MotorTask TOTAL=768 FREE=420',
          timestamp: now,
        ),
        isNull,
      );
      expect(
        collector.addLogLine(
          'STACK_TASK NAME=AdcTask TOTAL=256 FREE=200',
          timestamp: now,
        ),
        isNull,
      );
      expect(
        collector.addLogLine(
          'STACK_TASK NAME=CommTask TOTAL=640 FREE=300',
          timestamp: now,
        ),
        isNull,
      );
      expect(
        collector.addLogLine(
          'STACK_TASK NAME=MonitorTask TOTAL=576 FREE=180',
          timestamp: now,
        ),
        isNull,
      );
      expect(
        collector.addLogLine(
          'STACK_TASK NAME=HeaterTask TOTAL=448 FREE=390',
          timestamp: now,
        ),
        isNull,
      );

      final snapshot = collector.addLogLine(
        'STACK_SNAPSHOT_END',
        timestamp: now,
      );

      expect(snapshot, isNotNull);
      expect(snapshot!.tasks, hasLength(7));
      expect(snapshot.summary.totalWords, 3648);
      expect(snapshot.summary.totalFreeWords, 2210);
      expect(snapshot.summary.totalUsedWords, 1438);
      expect(snapshot.summary.riskiestTaskName, 'MonitorTask');
    });

    test('带日志级别前缀的快照行也能被解析', () {
      final collector = StackStatsCollector();
      final now = DateTime(2026, 5, 23, 12, 0, 0);

      expect(collector.addLogLine('[I] STACK_SNAPSHOT_BEGIN', timestamp: now), isNull);
      expect(
        collector.addLogLine(
          '[I] STACK_TASK NAME=ProtoTask TOTAL=384 FREE=320',
          timestamp: now,
        ),
        isNull,
      );
      expect(
        collector.addLogLine(
          '[I] STACK_TASK NAME=StateMachineTask TOTAL=576 FREE=400',
          timestamp: now,
        ),
        isNull,
      );
      expect(
        collector.addLogLine(
          '[I] STACK_TASK NAME=MotorTask TOTAL=768 FREE=420',
          timestamp: now,
        ),
        isNull,
      );
      expect(
        collector.addLogLine(
          '[I] STACK_TASK NAME=AdcTask TOTAL=256 FREE=200',
          timestamp: now,
        ),
        isNull,
      );
      expect(
        collector.addLogLine(
          '[I] STACK_TASK NAME=CommTask TOTAL=640 FREE=300',
          timestamp: now,
        ),
        isNull,
      );
      expect(
        collector.addLogLine(
          '[I] STACK_TASK NAME=MonitorTask TOTAL=576 FREE=180',
          timestamp: now,
        ),
        isNull,
      );
      expect(
        collector.addLogLine(
          '[I] STACK_TASK NAME=HeaterTask TOTAL=448 FREE=390',
          timestamp: now,
        ),
        isNull,
      );

      final snapshot = collector.addLogLine(
        '[I] STACK_SNAPSHOT_END',
        timestamp: now,
      );

      expect(snapshot, isNotNull);
      expect(snapshot!.tasks, hasLength(7));
    });

    test('带重复日志级别前缀的快照行也能被解析', () {
      final collector = StackStatsCollector();
      final now = DateTime(2026, 5, 23, 12, 0, 0);

      expect(
        collector.addLogLine('[I] [I] STACK_SNAPSHOT_BEGIN', timestamp: now),
        isNull,
      );
      expect(
        collector.addLogLine(
          '[I] [I] STACK_TASK NAME=ProtoTask TOTAL=384 FREE=320',
          timestamp: now,
        ),
        isNull,
      );
      expect(
        collector.addLogLine(
          '[I] [I] STACK_TASK NAME=StateMachineTask TOTAL=576 FREE=400',
          timestamp: now,
        ),
        isNull,
      );
      expect(
        collector.addLogLine(
          '[I] [I] STACK_TASK NAME=MotorTask TOTAL=768 FREE=420',
          timestamp: now,
        ),
        isNull,
      );
      expect(
        collector.addLogLine(
          '[I] [I] STACK_TASK NAME=AdcTask TOTAL=256 FREE=200',
          timestamp: now,
        ),
        isNull,
      );
      expect(
        collector.addLogLine(
          '[I] [I] STACK_TASK NAME=CommTask TOTAL=640 FREE=300',
          timestamp: now,
        ),
        isNull,
      );
      expect(
        collector.addLogLine(
          '[I] [I] STACK_TASK NAME=MonitorTask TOTAL=576 FREE=180',
          timestamp: now,
        ),
        isNull,
      );
      expect(
        collector.addLogLine(
          '[I] [I] STACK_TASK NAME=HeaterTask TOTAL=448 FREE=390',
          timestamp: now,
        ),
        isNull,
      );

      final snapshot = collector.addLogLine(
        '[I] [I] STACK_SNAPSHOT_END',
        timestamp: now,
      );

      expect(snapshot, isNotNull);
      expect(snapshot!.tasks, hasLength(7));
    });

    test('缺少任务时整份快照丢弃', () {
      final collector = StackStatsCollector();
      final now = DateTime(2026, 5, 23, 12, 0, 0);

      collector.addLogLine('STACK_SNAPSHOT_BEGIN', timestamp: now);
      collector.addLogLine(
        'STACK_TASK NAME=ProtoTask TOTAL=384 FREE=320',
        timestamp: now,
      );

      expect(
        collector.addLogLine('STACK_SNAPSHOT_END', timestamp: now),
        isNull,
      );
    });

    test('未知任务名被忽略但不污染已知任务', () {
      final collector = StackStatsCollector();
      final now = DateTime(2026, 5, 23, 12, 0, 0);

      collector.addLogLine('STACK_SNAPSHOT_BEGIN', timestamp: now);
      collector.addLogLine(
        'STACK_TASK NAME=UnknownTask TOTAL=100 FREE=10',
        timestamp: now,
      );
      collector.addLogLine(
        'STACK_TASK NAME=ProtoTask TOTAL=384 FREE=320',
        timestamp: now,
      );
      collector.addLogLine(
        'STACK_TASK NAME=StateMachineTask TOTAL=576 FREE=400',
        timestamp: now,
      );
      collector.addLogLine(
        'STACK_TASK NAME=MotorTask TOTAL=768 FREE=420',
        timestamp: now,
      );
      collector.addLogLine(
        'STACK_TASK NAME=AdcTask TOTAL=256 FREE=200',
        timestamp: now,
      );
      collector.addLogLine(
        'STACK_TASK NAME=CommTask TOTAL=640 FREE=300',
        timestamp: now,
      );
      collector.addLogLine(
        'STACK_TASK NAME=MonitorTask TOTAL=576 FREE=180',
        timestamp: now,
      );
      collector.addLogLine(
        'STACK_TASK NAME=HeaterTask TOTAL=448 FREE=390',
        timestamp: now,
      );

      final snapshot = collector.addLogLine(
        'STACK_SNAPSHOT_END',
        timestamp: now,
      );

      expect(snapshot, isNotNull);
      expect(
        snapshot!.tasks.any((task) => task.name == 'UnknownTask'),
        isFalse,
      );
    });

    test('快照缓冲区超过上限会自动复位，避免长期运行增长', () {
      final collector = StackStatsCollector(maxBufferedLines: 3);
      final now = DateTime(2026, 5, 23, 12, 0, 0);

      collector.addLogLine('STACK_SNAPSHOT_BEGIN', timestamp: now);
      collector.addLogLine(
        'STACK_TASK NAME=ProtoTask TOTAL=384 FREE=320',
        timestamp: now,
      );
      collector.addLogLine(
        'STACK_TASK NAME=StateMachineTask TOTAL=576 FREE=400',
        timestamp: now,
      );
      collector.addLogLine(
        'STACK_TASK NAME=MotorTask TOTAL=768 FREE=420',
        timestamp: now,
      );
      collector.addLogLine(
        'STACK_TASK NAME=AdcTask TOTAL=256 FREE=200',
        timestamp: now,
      );

      expect(collector.isCollecting, isFalse);
      expect(collector.bufferedLineCount, 0);
    });
  });
}
