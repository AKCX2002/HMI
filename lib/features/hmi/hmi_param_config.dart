// 运行时参数定义表 —— 与固件 `app_runtime_config_defaults.h` 完全对齐。
// 每个参数包含:
// - id: 参数 ID (对应固件 `RCFG_ID_*` 枚举值)
// - name: 中文名称
// - unit: 单位
// - min/max: 取值范围（源自固件 Doxygen 注释范围）
// - dgusAddr: DGUS 变量地址，公式 `0x2000 + (id - 0x10) * 2`
// - group: 分组标签

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

/// 全部运行时参数定义表 (与固件 `packer_runtime_config_id_t` 一一对应)
const List<HmiParamDef> kParamDefs = <HmiParamDef>[
  // ══════════════════════════════════════════════════════════════════
  //  步进运动参数 (ID 0x10~0x17, DGUS 0x2000~0x200E)
  // ══════════════════════════════════════════════════════════════════
  HmiParamDef(
    id: 0x10,
    name: '出袋轴频率',
    unit: 'Hz',
    min: 0,
    max: 200000,
    dgusAddr: 0x2000,
    group: '步进运动参数',
  ),
  HmiParamDef(
    id: 0x11,
    name: '拉断频率(43轴1)',
    unit: 'Hz',
    min: 0,
    max: 200000,
    dgusAddr: 0x2002,
    group: '步进运动参数',
  ),
  HmiParamDef(
    id: 0x12,
    name: '压杆下压频率(2/3/4)',
    unit: 'Hz',
    min: 100,
    max: 80000,
    dgusAddr: 0x2004,
    group: '步进运动参数',
  ),
  HmiParamDef(
    id: 0x13,
    name: '压杆归位频率(2/3/4)',
    unit: 'Hz',
    min: 100,
    max: 80000,
    dgusAddr: 0x2006,
    group: '步进运动参数',
  ),
  HmiParamDef(
    id: 0x14,
    name: '步进起步频率',
    unit: 'Hz',
    min: 50,
    max: 5000,
    dgusAddr: 0x2008,
    group: '步进运动参数',
  ),
  HmiParamDef(
    id: 0x15,
    name: '加速斜率',
    unit: 'Hz/s',
    min: 100,
    max: 100000,
    dgusAddr: 0x200A,
    group: '步进运动参数',
  ),
  HmiParamDef(
    id: 0x16,
    name: '减速斜率',
    unit: 'Hz/s',
    min: 100,
    max: 100000,
    dgusAddr: 0x200C,
    group: '步进运动参数',
  ),
  HmiParamDef(
    id: 0x17,
    name: '自检3/4轴测试频率',
    unit: 'Hz',
    min: 100,
    max: 80000,
    dgusAddr: 0x200E,
    group: '步进运动参数',
  ),

  // ══════════════════════════════════════════════════════════════════
  //  流程延时/超时 (ID 0x20~0x33, DGUS 0x2020~0x2046)
  // ══════════════════════════════════════════════════════════════════
  HmiParamDef(
    id: 0x20,
    name: '上电稳定延时',
    unit: 'ms',
    min: 0,
    max: 60000,
    dgusAddr: 0x2020,
    group: '流程延时/超时',
  ),
  HmiParamDef(
    id: 0x21,
    name: '自检驻留时间',
    unit: 'ms',
    min: 0,
    max: 60000,
    dgusAddr: 0x2022,
    group: '流程延时/超时',
  ),
  HmiParamDef(
    id: 0x22,
    name: '自检挡板闭合等待',
    unit: 'ms',
    min: 0,
    max: 60000,
    dgusAddr: 0x2024,
    group: '流程延时/超时',
  ),
  HmiParamDef(
    id: 0x23,
    name: '自检压杆限位超时',
    unit: 'ms',
    min: 100,
    max: 60000,
    dgusAddr: 0x2026,
    group: '流程延时/超时',
  ),
  HmiParamDef(
    id: 0x24,
    name: '正式出袋超时',
    unit: 'ms',
    min: 100,
    max: 60000,
    dgusAddr: 0x2028,
    group: '流程延时/超时',
  ),
  HmiParamDef(
    id: 0x25,
    name: '校准回抽后延迟',
    unit: 'ms',
    min: 0,
    max: 60000,
    dgusAddr: 0x202A,
    group: '流程延时/超时',
  ),
  HmiParamDef(
    id: 0x26,
    name: '出袋收尾挡板驻留',
    unit: 'ms',
    min: 0,
    max: 60000,
    dgusAddr: 0x202C,
    group: '流程延时/超时',
  ),
  HmiParamDef(
    id: 0x27,
    name: '封口挡板闭合等待',
    unit: 'ms',
    min: 0,
    max: 60000,
    dgusAddr: 0x202E,
    group: '流程延时/超时',
  ),
  HmiParamDef(
    id: 0x28,
    name: '压杆回抽超时',
    unit: 'ms',
    min: 10,
    max: 60000,
    dgusAddr: 0x2030,
    group: '流程延时/超时',
  ),
  HmiParamDef(
    id: 0x29,
    name: '封口保持时间',
    unit: 'ms',
    min: 10,
    max: 30000,
    dgusAddr: 0x2032,
    group: '流程延时/超时',
  ),
  HmiParamDef(
    id: 0x2A,
    name: '归位联合超时(2/3/4)',
    unit: 'ms',
    min: 10000,
    max: 60000,
    dgusAddr: 0x2034,
    group: '流程延时/超时',
  ),
  HmiParamDef(
    id: 0x2B,
    name: '推杆推出前延迟',
    unit: 'ms',
    min: 0,
    max: 60000,
    dgusAddr: 0x2036,
    group: '流程延时/超时',
  ),
  HmiParamDef(
    id: 0x2C,
    name: '推杆前进时间',
    unit: 'ms',
    min: 0,
    max: 60000,
    dgusAddr: 0x2038,
    group: '流程延时/超时',
  ),
  HmiParamDef(
    id: 0x2D,
    name: '推杆推出停留',
    unit: 'ms',
    min: 0,
    max: 60000,
    dgusAddr: 0x203A,
    group: '流程延时/超时',
  ),
  HmiParamDef(
    id: 0x2E,
    name: '推杆回收时间',
    unit: 'ms',
    min: 0,
    max: 60000,
    dgusAddr: 0x203C,
    group: '流程延时/超时',
  ),
  HmiParamDef(
    id: 0x2F,
    name: '复位驻留时间',
    unit: 'ms',
    min: 0,
    max: 60000,
    dgusAddr: 0x203E,
    group: '流程延时/超时',
  ),
  HmiParamDef(
    id: 0x30,
    name: '故障恢复等待',
    unit: 'ms',
    min: 0,
    max: 60000,
    dgusAddr: 0x2040,
    group: '流程延时/超时',
  ),
  HmiParamDef(
    id: 0x31,
    name: '光电消抖时间',
    unit: 'ms',
    min: 0,
    max: 1000,
    dgusAddr: 0x2042,
    group: '流程延时/超时',
  ),
  HmiParamDef(
    id: 0x32,
    name: '历史脱离超时',
    unit: 'ms',
    min: 0,
    max: 60000,
    dgusAddr: 0x2044,
    group: '流程延时/超时',
  ),
  HmiParamDef(
    id: 0x33,
    name: '历史寻找超时',
    unit: 'ms',
    min: 0,
    max: 60000,
    dgusAddr: 0x2046,
    group: '流程延时/超时',
  ),

  // ══════════════════════════════════════════════════════════════════
  //  0x40~0x43: 已移除，出袋机械固定参数改为固件编译期 APP_CFG_BAG_* 宏
  //  出袋运行参数 (ID 0x44~0x47, DGUS 0x2068~0x206E)
  // ══════════════════════════════════════════════════════════════════
  HmiParamDef(
    id: 0x44,
    name: '校准回抽长度',
    unit: '0.001mm',
    min: 0,
    max: 1000000,
    dgusAddr: 0x2068,
    group: '出袋机械尺寸',
  ),
  HmiParamDef(
    id: 0x45,
    name: '正式出袋长度',
    unit: '0.001mm',
    min: 1000,
    max: 2000000,
    dgusAddr: 0x206A,
    group: '出袋机械尺寸',
  ),
  HmiParamDef(
    id: 0x46,
    name: '出袋默认线速度',
    unit: '0.001mm/s',
    min: 1000,
    max: 500000,
    dgusAddr: 0x206C,
    group: '出袋机械尺寸',
  ),
  HmiParamDef(
    id: 0x47,
    name: '出袋最高线速度',
    unit: '0.001mm/s',
    min: 1000,
    max: 500000,
    dgusAddr: 0x206E,
    group: '出袋机械尺寸',
  ),

  // ══════════════════════════════════════════════════════════════════
  //  0x48~0x4B: 已移除，压杆机械固定参数改为固件编译期 APP_CFG_PRESS_* 宏
  //  压杆运行参数 (ID 0x4C~0x4F, DGUS 0x2078~0x207E)
  // ══════════════════════════════════════════════════════════════════
  HmiParamDef(
    id: 0x4C,
    name: '压杆回IN1脉冲保护位移',
    unit: '0.001mm',
    min: 1000,
    max: 1000000,
    dgusAddr: 0x2078,
    group: '压杆机械尺寸',
  ),
  HmiParamDef(
    id: 0x4D,
    name: '压杆下压目标位移',
    unit: '0.001mm',
    min: 1000,
    max: 1000000,
    dgusAddr: 0x207A,
    group: '压杆机械尺寸',
  ),
  HmiParamDef(
    id: 0x4E,
    name: '扒口角度',
    unit: '0.1°',
    min: 50,
    max: 3500,
    dgusAddr: 0x207C,
    group: '压杆机械尺寸',
  ),
  HmiParamDef(
    id: 0x4F,
    name: '拉断长度',
    unit: '0.001mm',
    min: 1000,
    max: 1000000,
    dgusAddr: 0x207E,
    group: '压杆机械尺寸',
  ),

  // ══════════════════════════════════════════════════════════════════
  //  加热/打印机 (ID 0x50~0x54, DGUS 0x2080~0x2088)
  // ══════════════════════════════════════════════════════════════════
  HmiParamDef(
    id: 0x50,
    name: '加热占空比周期',
    unit: 'ms',
    min: 100,
    max: 10000,
    dgusAddr: 0x2080,
    group: '加热/打印机',
  ),
  HmiParamDef(
    id: 0x51,
    name: '加热占空比',
    unit: '‰',
    min: 0,
    max: 200,
    dgusAddr: 0x2082,
    group: '加热/打印机',
  ),
  HmiParamDef(
    id: 0x53,
    name: '打印触发出袋长度',
    unit: '0.001mm',
    min: 0,
    max: 1000000,
    dgusAddr: 0x2086,
    group: '加热/打印机',
  ),
  HmiParamDef(
    id: 0x54,
    name: '打印机发送超时',
    unit: 'ms',
    min: 1,
    max: 1000,
    dgusAddr: 0x2088,
    group: '加热/打印机',
  ),

  // ══════════════════════════════════════════════════════════════════
  //  0x55~0x63: 已移除，功率参数改为固件编译期 APP_CFG_POWER_* 宏
  // ══════════════════════════════════════════════════════════════════

  // ══════════════════════════════════════════════════════════════════
  //  0x70~0x72: 已移除，监控/看门狗参数改为固件编译期 APP_CFG_* 宏
  // ══════════════════════════════════════════════════════════════════

  // ══════════════════════════════════════════════════════════════════
  //  挡板时序与自检 (ID 0x80~0x83, DGUS 0x20E0~0x20EC)
  //  注意: 历史开关标志位域(0x52)已移除并固定为固件内建策略
  // ══════════════════════════════════════════════════════════════════
  HmiParamDef(
    id: 0x80,
    name: '挡板全程时间',
    unit: 'ms',
    min: 0,
    max: 60000,
    dgusAddr: 0x20E0,
    group: '挡板时序',
  ),
  HmiParamDef(
    id: 0x81,
    name: '挡板预张开时间',
    unit: 'ms',
    min: 0,
    max: 60000,
    dgusAddr: 0x20E2,
    group: '挡板时序',
  ),
  HmiParamDef(
    id: 0x82,
    name: '挡板归位补偿时间',
    unit: 'ms',
    min: 0,
    max: 60000,
    dgusAddr: 0x20E4,
    group: '挡板时序',
  ),
  HmiParamDef(
    id: 0x83,
    name: '自检轴2回IN1频率',
    unit: 'Hz',
    min: 100,
    max: 80000,
    dgusAddr: 0x20E6,
    group: '步进运动参数',
  ),
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
