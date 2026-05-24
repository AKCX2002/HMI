import 'dart:convert';
import 'dart:typed_data';

import 'stack_stats.dart';

enum HmiSessionParamType {
  u8(0x01),
  u16(0x02),
  u32(0x03),
  s16(0x04),
  s32(0x05);

  const HmiSessionParamType(this.wireValue);

  final int wireValue;

  static HmiSessionParamType fromWireValue(int value) {
    for (final item in values) {
      if (item.wireValue == value) {
        return item;
      }
    }
    return HmiSessionParamType.u32;
  }
}

enum HmiSessionTaskId {
  protoTask(0x01, 'ProtoTask'),
  stateMachineTask(0x02, 'StateMachineTask'),
  motorTask(0x03, 'MotorTask'),
  adcTask(0x04, 'AdcTask'),
  commTask(0x05, 'CommTask'),
  monitorTask(0x06, 'MonitorTask'),
  heaterTask(0x07, 'HeaterTask');

  const HmiSessionTaskId(this.wireValue, this.taskName);

  final int wireValue;
  final String taskName;

  static HmiSessionTaskId? tryParse(int value) {
    for (final item in values) {
      if (item.wireValue == value) {
        return item;
      }
    }
    return null;
  }
}

class HmiSessionGroupDef {
  const HmiSessionGroupDef({
    required this.groupId,
    required this.order,
    required this.flags,
    required this.groupKey,
    required this.groupName,
  });

  final int groupId;
  final int order;
  final int flags;
  final String groupKey;
  final String groupName;
}

class HmiSessionParamDef {
  const HmiSessionParamDef({
    required this.paramId,
    required this.groupId,
    required this.type,
    required this.flags,
    required this.scale,
    required this.minValue,
    required this.maxValue,
    required this.defaultValue,
    required this.stepValue,
    required this.paramKey,
    required this.paramName,
    required this.unit,
  });

  final int paramId;
  final int groupId;
  final HmiSessionParamType type;
  final int flags;
  final int scale;
  final int minValue;
  final int maxValue;
  final int defaultValue;
  final int stepValue;
  final String paramKey;
  final String paramName;
  final String unit;

  bool get isReadOnly => (flags & 0x0004) != 0;
  int get id => paramId;
  String get name => paramName;
  int get min => minValue;
  int get max => maxValue;
}

class HmiSessionGroupCatalogPage {
  const HmiSessionGroupCatalogPage({
    required this.totalCount,
    required this.nextOffset,
    required this.groups,
  });

  final int totalCount;
  final int nextOffset;
  final List<HmiSessionGroupDef> groups;
}

class HmiSessionParamCatalogPage {
  const HmiSessionParamCatalogPage({
    required this.totalCount,
    required this.nextOffset,
    required this.params,
  });

  final int totalCount;
  final int nextOffset;
  final List<HmiSessionParamDef> params;
}

int _readU16(Uint8List bytes, int offset) {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

int _readI16(Uint8List bytes, int offset) {
  final value = _readU16(bytes, offset);
  return value >= 0x8000 ? value - 0x10000 : value;
}

int _readI32(Uint8List bytes, int offset) {
  final value =
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
  return value >= 0x80000000 ? value - 0x100000000 : value;
}

String _readUtf8(Uint8List bytes, int offset, int len) {
  return utf8.decode(bytes.sublist(offset, offset + len));
}

HmiSessionGroupCatalogPage parseGroupCatalogPage(Uint8List payload) {
  if (payload.length < 4 || payload[0] != 0x00) {
    throw const FormatException('invalid group catalog payload');
  }

  final count = payload[1];
  final totalCount = payload[2];
  final nextOffset = payload[3];
  var cursor = 4;
  final groups = <HmiSessionGroupDef>[];

  for (var i = 0; i < count; i++) {
    if (cursor + 8 > payload.length) {
      throw const FormatException('truncated group record');
    }
    final groupId = _readU16(payload, cursor);
    final order = _readU16(payload, cursor + 2);
    final flags = _readU16(payload, cursor + 4);
    final keyLen = payload[cursor + 6];
    final nameLen = payload[cursor + 7];
    cursor += 8;
    if (cursor + keyLen + nameLen > payload.length) {
      throw const FormatException('truncated group text');
    }
    final groupKey = _readUtf8(payload, cursor, keyLen);
    cursor += keyLen;
    final groupName = _readUtf8(payload, cursor, nameLen);
    cursor += nameLen;
    groups.add(
      HmiSessionGroupDef(
        groupId: groupId,
        order: order,
        flags: flags,
        groupKey: groupKey,
        groupName: groupName,
      ),
    );
  }

  return HmiSessionGroupCatalogPage(
    totalCount: totalCount,
    nextOffset: nextOffset,
    groups: groups,
  );
}

HmiSessionParamCatalogPage parseParamCatalogPage(Uint8List payload) {
  if (payload.length < 4 || payload[0] != 0x00) {
    throw const FormatException('invalid param catalog payload');
  }

  final count = payload[1];
  final totalCount = payload[2];
  final nextOffset = payload[3];
  var cursor = 4;
  final params = <HmiSessionParamDef>[];

  for (var i = 0; i < count; i++) {
    if (cursor + 27 > payload.length) {
      throw const FormatException('truncated param record');
    }
    final paramId = _readU16(payload, cursor);
    final groupId = _readU16(payload, cursor + 2);
    final type = HmiSessionParamType.fromWireValue(payload[cursor + 4]);
    final flags = _readU16(payload, cursor + 5);
    final scale = _readI16(payload, cursor + 7);
    final minValue = _readI32(payload, cursor + 9);
    final maxValue = _readI32(payload, cursor + 13);
    final defaultValue = _readI32(payload, cursor + 17);
    final stepValue = _readI32(payload, cursor + 21);
    final keyLen = payload[cursor + 25];
    final nameLen = payload[cursor + 26];
    final unitLen = payload[cursor + 27];
    cursor += 28;
    if (cursor + keyLen + nameLen + unitLen > payload.length) {
      throw const FormatException('truncated param text');
    }
    final paramKey = _readUtf8(payload, cursor, keyLen);
    cursor += keyLen;
    final paramName = _readUtf8(payload, cursor, nameLen);
    cursor += nameLen;
    final unit = _readUtf8(payload, cursor, unitLen);
    cursor += unitLen;

    params.add(
      HmiSessionParamDef(
        paramId: paramId,
        groupId: groupId,
        type: type,
        flags: flags,
        scale: scale,
        minValue: minValue,
        maxValue: maxValue,
        defaultValue: defaultValue,
        stepValue: stepValue,
        paramKey: paramKey,
        paramName: paramName,
        unit: unit,
      ),
    );
  }

  return HmiSessionParamCatalogPage(
    totalCount: totalCount,
    nextOffset: nextOffset,
    params: params,
  );
}

StackSnapshot parseStackSnapshotPush(Uint8List payload, {DateTime? timestamp}) {
  if (payload.isEmpty) {
    throw const FormatException('invalid stack snapshot payload');
  }

  final count = payload[0];
  var cursor = 1;
  final tasks = <StackTaskSnapshot>[];
  final now = timestamp ?? DateTime.now();

  for (var i = 0; i < count; i++) {
    if (cursor + 5 > payload.length) {
      throw const FormatException('truncated stack snapshot payload');
    }
    final taskId = HmiSessionTaskId.tryParse(payload[cursor]);
    final totalWords = _readU16(payload, cursor + 1);
    final freeWords = _readU16(payload, cursor + 3);
    cursor += 5;
    if (taskId == null) {
      continue;
    }
    final usedWords = totalWords >= freeWords ? totalWords - freeWords : 0;
    final usedRatio = totalWords == 0 ? 0.0 : usedWords / totalWords;
    tasks.add(
      StackTaskSnapshot(
        name: taskId.taskName,
        totalWords: totalWords,
        freeWords: freeWords,
        usedWords: usedWords,
        usedRatio: usedRatio,
        timestamp: now,
      ),
    );
  }

  final totalWords = tasks.fold<int>(0, (sum, item) => sum + item.totalWords);
  final totalFreeWords = tasks.fold<int>(0, (sum, item) => sum + item.freeWords);
  final totalUsedWords = tasks.fold<int>(0, (sum, item) => sum + item.usedWords);
  final riskiestTask = tasks.isEmpty
      ? null
      : tasks.reduce(
          (lhs, rhs) => lhs.usedRatio >= rhs.usedRatio ? lhs : rhs,
        );

  return StackSnapshot(
    timestamp: now,
    tasks: tasks,
    summary: StackSummarySnapshot(
      totalWords: totalWords,
      totalFreeWords: totalFreeWords,
      totalUsedWords: totalUsedWords,
      riskiestTaskName: riskiestTask?.name ?? '-',
    ),
  );
}
