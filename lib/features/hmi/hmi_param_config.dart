import 'hmi_protocol.dart';

/// 运行时参数定义 —— 与下位机 app_runtime_config_defaults.h 完全对齐。
///
/// 每个参数包含:
/// - [id]: 参数 ID (对应协议 Y1 字段)
/// - [name]: 中文名称
/// - [unit]: 单位
/// - [min]/[max]: 取值范围
/// - [dgusAddr]: DGUS 屏幕变量地址
/// - [group]: 分组标签

class HmiParamDef {
  const HmiParamDef({
    required this.id,
    required this.name,
    required this.unit,
    required this.min,
    required this.max,
    required this.dgusAddr,
    required this.group,
  });

  final int id;
  final String name;
  final String unit;
  final int min;
  final int max;
  final int dgusAddr;
  final String group;
}

/// 参数分组枚举
enum HmiParamGroup {
  stepper('步进运动参数'),
  timing('流程延时/超时'),
  bagMech('出袋机械尺寸'),
  pressMech('压杆机械尺寸'),
  heaterPrinter('加热/打印机'),
  led('LED 闪烁'),
  monitor('监控/看门狗'),
  selfCheck('自检开关');

  const HmiParamGroup(this.label);
  final String label;
}

/// 全部运行时参数定义表 (53 个参数, 与固件 packer_runtime_config 一一对应)
const List<HmiParamDef> kParamDefs = <HmiParamDef>[

  // ── 步进运动参数 (0x10~0x16) ──
  HmiParamDef(id: 0x10, name: '出袋轴频率',          unit: 'Hz',
      min: 100, max: 200000, dgusAddr: 0x2000, group: '步进运动参数'),
  HmiParamDef(id: 0x11, name: '拉断回拉频率',        unit: 'Hz',
      min: 100, max: 200000, dgusAddr: 0x2002, group: '步进运动参数'),
  HmiParamDef(id: 0x12, name: '2号轴压下频率',       unit: 'Hz',
      min: 100, max: 80000,  dgusAddr: 0x2004, group: '步进运动参数'),
  HmiParamDef(id: 0x13, name: '归位频率',             unit: 'Hz',
      min: 100, max: 80000,  dgusAddr: 0x2006, group: '步进运动参数'),
  HmiParamDef(id: 0x14, name: '步进起步频率',        unit: 'Hz',
      min: 50,  max: 5000,   dgusAddr: 0x2008, group: '步进运动参数'),
  HmiParamDef(id: 0x15, name: '加速斜率',             unit: 'Hz/s',
      min: 100, max: 100000, dgusAddr: 0x200A, group: '步进运动参数'),
  HmiParamDef(id: 0x16, name: '减速斜率',             unit: 'Hz/s',
      min: 100, max: 100000, dgusAddr: 0x200C, group: '步进运动参数'),

  // ── 流程延时/超时 (0x20~0x33) ──
  HmiParamDef(id: 0x20, name: '上电稳定延时',        unit: 'ms',
      min: 0,   max: 60000,  dgusAddr: 0x2010, group: '流程延时/超时'),
  HmiParamDef(id: 0x21, name: '自检驻留时间',        unit: 'ms',
      min: 0,   max: 60000,  dgusAddr: 0x2012, group: '流程延时/超时'),
  HmiParamDef(id: 0x22, name: '自检挡板闭合等待',    unit: 'ms',
      min: 0,   max: 60000,  dgusAddr: 0x2014, group: '流程延时/超时'),
  HmiParamDef(id: 0x23, name: '自检压杆限位超时',    unit: 'ms',
      min: 100, max: 60000,  dgusAddr: 0x2016, group: '流程延时/超时'),
  HmiParamDef(id: 0x24, name: '正式出袋超时',        unit: 'ms',
      min: 100, max: 60000,  dgusAddr: 0x2018, group: '流程延时/超时'),
  HmiParamDef(id: 0x25, name: '校准回抽后延迟',      unit: 'ms',
      min: 0,   max: 60000,  dgusAddr: 0x201A, group: '流程延时/超时'),
  HmiParamDef(id: 0x26, name: '出袋收尾挡板驻留',    unit: 'ms',
      min: 0,   max: 60000,  dgusAddr: 0x201C, group: '流程延时/超时'),
  HmiParamDef(id: 0x27, name: '封口挡板闭合等待',    unit: 'ms',
      min: 0,   max: 60000,  dgusAddr: 0x2020, group: '流程延时/超时'),
  HmiParamDef(id: 0x28, name: '压杆回抽超时',        unit: 'ms',
      min: 10,  max: 60000,  dgusAddr: 0x2022, group: '流程延时/超时'),
  HmiParamDef(id: 0x29, name: '封口保持时间',        unit: 'ms',
      min: 10,  max: 30000,  dgusAddr: 0x2024, group: '流程延时/超时'),
  HmiParamDef(id: 0x2A, name: '归位联合动作超时',    unit: 'ms',
      min: 100, max: 60000,  dgusAddr: 0x2026, group: '流程延时/超时'),
  HmiParamDef(id: 0x2B, name: '推杆推出前延迟',      unit: 'ms',
      min: 0,   max: 60000,  dgusAddr: 0x2028, group: '流程延时/超时'),
  HmiParamDef(id: 0x2C, name: '推杆前进时间',        unit: 'ms',
      min: 0,   max: 60000,  dgusAddr: 0x202A, group: '流程延时/超时'),
  HmiParamDef(id: 0x2D, name: '推杆推出停留',        unit: 'ms',
      min: 0,   max: 60000,  dgusAddr: 0x202C, group: '流程延时/超时'),
  HmiParamDef(id: 0x2E, name: '推杆回收时间',        unit: 'ms',
      min: 0,   max: 60000,  dgusAddr: 0x202E, group: '流程延时/超时'),
  HmiParamDef(id: 0x2F, name: '复位驻留时间',        unit: 'ms',
      min: 0,   max: 60000,  dgusAddr: 0x2030, group: '流程延时/超时'),
  HmiParamDef(id: 0x30, name: '故障恢复等待',        unit: 'ms',
      min: 0,   max: 60000,  dgusAddr: 0x2032, group: '流程延时/超时'),
  HmiParamDef(id: 0x31, name: '光电消抖时间',        unit: 'ms',
      min: 0,   max: 1000,   dgusAddr: 0x2034, group: '流程延时/超时'),
  HmiParamDef(id: 0x32, name: '历史脱离超时',        unit: 'ms',
      min: 0,   max: 60000,  dgusAddr: 0x2036, group: '流程延时/超时'),
  HmiParamDef(id: 0x33, name: '历史寻找超时',        unit: 'ms',
      min: 0,   max: 60000,  dgusAddr: 0x2038, group: '流程延时/超时'),

  // ── 出袋机械尺寸 (0x40~0x47) ──
  HmiParamDef(id: 0x40, name: '出袋电机脉冲/圈',     unit: 'PUL',
      min: 200, max: 100000, dgusAddr: 0x2040, group: '出袋机械尺寸'),
  HmiParamDef(id: 0x41, name: '出袋滚轴直径',        unit: '0.001mm',
      min: 1000,max: 200000, dgusAddr: 0x2042, group: '出袋机械尺寸'),
  HmiParamDef(id: 0x42, name: '出袋主动轮齿数',      unit: 'T',
      min: 1,   max: 200,    dgusAddr: 0x2044, group: '出袋机械尺寸'),
  HmiParamDef(id: 0x43, name: '出袋从动轮齿数',      unit: 'T',
      min: 1,   max: 200,    dgusAddr: 0x2046, group: '出袋机械尺寸'),
  HmiParamDef(id: 0x44, name: '校准回抽长度',        unit: '0.001mm',
      min: 0,   max: 1000000,dgusAddr: 0x2048, group: '出袋机械尺寸'),
  HmiParamDef(id: 0x45, name: '正式出袋长度',        unit: '0.001mm',
      min: 1000,max: 2000000,dgusAddr: 0x204A, group: '出袋机械尺寸'),
  HmiParamDef(id: 0x46, name: '出袋默认线速度',      unit: '0.001mm/s',
      min: 1000,max: 500000, dgusAddr: 0x204C, group: '出袋机械尺寸'),
  HmiParamDef(id: 0x47, name: '出袋最高线速度',      unit: '0.001mm/s',
      min: 1000,max: 500000, dgusAddr: 0x204E, group: '出袋机械尺寸'),

  // ── 压杆机械尺寸 (0x48~0x4C) ──
  HmiParamDef(id: 0x48, name: '压杆电机脉冲/圈',     unit: 'PUL',
      min: 200, max: 100000, dgusAddr: 0x2050, group: '压杆机械尺寸'),
  HmiParamDef(id: 0x49, name: '压杆主动轮齿数',      unit: 'T',
      min: 1,   max: 200,    dgusAddr: 0x2052, group: '压杆机械尺寸'),
  HmiParamDef(id: 0x4A, name: '压杆从动轮齿数',      unit: 'T',
      min: 1,   max: 200,    dgusAddr: 0x2054, group: '压杆机械尺寸'),
  HmiParamDef(id: 0x4B, name: '压杆同步轮节圆直径',   unit: '0.001mm',
      min: 1000,max: 200000, dgusAddr: 0x2056, group: '压杆机械尺寸'),
  HmiParamDef(id: 0x4C, name: '压杆回拉目标位移',    unit: '0.001mm',
      min: 1000,max: 1000000,dgusAddr: 0x2058, group: '压杆机械尺寸'),

  // ── 加热/打印机 (0x50~0x53) ──
  HmiParamDef(id: 0x50, name: '加热翻转周期',        unit: 'ms',
      min: 100, max: 10000,  dgusAddr: 0x2060, group: '加热/打印机'),
  HmiParamDef(id: 0x51, name: '打印机联动开关',      unit: '',
      min: 0,   max: 1,      dgusAddr: 0x2062, group: '加热/打印机'),
  HmiParamDef(id: 0x52, name: '打印触发出袋长度',    unit: '0.001mm',
      min: 0,   max: 1000000,dgusAddr: 0x2064, group: '加热/打印机'),
  HmiParamDef(id: 0x53, name: '打印机发送超时',      unit: 'ms',
      min: 1,   max: 1000,   dgusAddr: 0x2066, group: '加热/打印机'),

  // ── LED 闪烁周期 (0x60~0x65) ──
  HmiParamDef(id: 0x60, name: '上电/自检LED闪烁',    unit: 'ms',
      min: 10,  max: 5000,   dgusAddr: 0x2080, group: 'LED 闪烁'),
  HmiParamDef(id: 0x61, name: '空闲LED闪烁',         unit: 'ms',
      min: 10,  max: 5000,   dgusAddr: 0x2082, group: 'LED 闪烁'),
  HmiParamDef(id: 0x62, name: '校准LED闪烁',         unit: 'ms',
      min: 10,  max: 5000,   dgusAddr: 0x2084, group: 'LED 闪烁'),
  HmiParamDef(id: 0x63, name: '执行LED闪烁',         unit: 'ms',
      min: 10,  max: 5000,   dgusAddr: 0x2086, group: 'LED 闪烁'),
  HmiParamDef(id: 0x64, name: '封口保持LED闪烁',     unit: 'ms',
      min: 10,  max: 5000,   dgusAddr: 0x2088, group: 'LED 闪烁'),
  HmiParamDef(id: 0x65, name: '故障LED闪烁',         unit: 'ms',
      min: 10,  max: 5000,   dgusAddr: 0x208A, group: 'LED 闪烁'),

  // ── 监控/看门狗 (0x70~0x72) ──
  HmiParamDef(id: 0x70, name: '喂狗周期',             unit: 'ms',
      min: 10,  max: 10000,  dgusAddr: 0x20A0, group: '监控/看门狗'),
  HmiParamDef(id: 0x71, name: '栈水位日志周期',      unit: 'ms',
      min: 1000,max: 3600000,dgusAddr: 0x20A2, group: '监控/看门狗'),
  HmiParamDef(id: 0x72, name: 'CPU使用率日志周期',   unit: 'ms',
      min: 1000,max: 3600000,dgusAddr: 0x20A4, group: '监控/看门狗'),

  // ── 自检开关 (0x80~0x82) ──
  HmiParamDef(id: 0x80, name: '上电袋口校准开关',    unit: '',
      min: 0,   max: 1,      dgusAddr: 0x20C0, group: '自检开关'),
  HmiParamDef(id: 0x81, name: '自检压杆测试开关',    unit: '',
      min: 0,   max: 1,      dgusAddr: 0x20C2, group: '自检开关'),
  HmiParamDef(id: 0x82, name: '打印机旁路开关',      unit: '',
      min: 0,   max: 1,      dgusAddr: 0x20C4, group: '自检开关'),
];

/// 按分组标签获取参数列表
Map<String, List<HmiParamDef>> get kParamDefsByGroup {
  final map = <String, List<HmiParamDef>>{};
  for (final p in kParamDefs) {
    map.putIfAbsent(p.group, () => <HmiParamDef>[]).add(p);
  }
  return map;
}

/// 按参数 ID 查找定义
HmiParamDef? findParamDef(int id) {
  for (final p in kParamDefs) {
    if (p.id == id) return p;
  }
  return null;
}
