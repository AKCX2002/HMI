import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hmi_host/features/hmi/hmi_session_catalog.dart';

void main() {
  test('parses paged group catalog payload', () {
    final groupName1 = utf8.encode('步进运动参数');
    final groupName2 = utf8.encode('流程延时/超时');
    final payload = Uint8List.fromList(<int>[
      0x00,
      0x02,
      0x07,
      0x02,
      0x01,
      0x00,
      0x01,
      0x00,
      0x01,
      0x00,
      0x06,
      groupName1.length,
      ...utf8.encode('motion'),
      ...groupName1,
      0x02,
      0x00,
      0x02,
      0x00,
      0x00,
      0x00,
      0x05,
      groupName2.length,
      ...utf8.encode('delay'),
      ...groupName2,
    ]);

    final page = parseGroupCatalogPage(payload);

    expect(page.totalCount, 7);
    expect(page.nextOffset, 2);
    expect(page.groups, hasLength(2));
    expect(page.groups.first.groupId, 1);
    expect(page.groups.first.groupKey, 'motion');
    expect(page.groups.first.groupName, '步进运动参数');
    expect(page.groups.last.groupId, 2);
    expect(page.groups.last.order, 2);
  });

  test('parses paged parameter catalog payload', () {
    final paramName = utf8.encode('出袋轴频率');
    final payload = BytesBuilder()..add(<int>[0x00, 0x01, 0x35, 0x01]);
    payload.add(<int>[0x10, 0x00]);
    payload.add(<int>[0x01, 0x00]);
    payload.add(<int>[0x03]);
    payload.add(<int>[0x00, 0x00]);
    payload.add(<int>[0x00, 0x00]);
    payload.add(<int>[0x32, 0x00, 0x00, 0x00]);
    payload.add(<int>[0x40, 0x0D, 0x03, 0x00]);
    payload.add(<int>[0x32, 0x00, 0x00, 0x00]);
    payload.add(<int>[0x64, 0x00, 0x00, 0x00]);
    payload.add(<int>[0x06, paramName.length, 0x02]);
    payload.add(utf8.encode('bag_hz'));
    payload.add(paramName);
    payload.add(utf8.encode('Hz'));

    final page = parseParamCatalogPage(payload.toBytes());

    expect(page.totalCount, 0x35);
    expect(page.nextOffset, 1);
    expect(page.params, hasLength(1));
    final param = page.params.single;
    expect(param.paramId, 0x10);
    expect(param.groupId, 1);
    expect(param.type, HmiSessionParamType.u32);
    expect(param.minValue, 50);
    expect(param.maxValue, 200000);
    expect(param.defaultValue, 50);
    expect(param.stepValue, 100);
    expect(param.paramKey, 'bag_hz');
    expect(param.paramName, '出袋轴频率');
    expect(param.unit, 'Hz');
  });

  test('parses stack snapshot push payload', () {
    final payload = Uint8List.fromList(<int>[
      0x02,
      HmiSessionTaskId.protoTask.wireValue,
      0x80,
      0x01,
      0x40,
      0x01,
      HmiSessionTaskId.monitorTask.wireValue,
      0x40,
      0x02,
      0xB4,
      0x00,
    ]);

    final snapshot = parseStackSnapshotPush(payload);

    expect(snapshot.tasks, hasLength(2));
    expect(snapshot.tasks.first.name, 'ProtoTask');
    expect(snapshot.tasks.first.totalWords, 384);
    expect(snapshot.tasks.first.freeWords, 320);
    expect(snapshot.summary.totalWords, 960);
    expect(snapshot.summary.totalFreeWords, 500);
    expect(snapshot.summary.riskiestTaskName, 'MonitorTask');
  });
}
