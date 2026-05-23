# Stack Stats HMI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 HMI 基于固件日志实时显示每个任务的栈总量、已占用、剩余和风险总览，并将结构化快照持续写入本地 `jsonl`，同时保证长期运行内存受控。

**Architecture:** 固件继续通过现有 DGUS 日志通道输出栈快照，但日志格式升级为“可确定性解析的完整快照”。HMI 把解析、内存聚合和滚动持久化收口到控制器侧，页面只展示总览卡片和任务表格，内存中仅保留有限窗口，历史数据只落盘不常驻。

**Tech Stack:** STM32 HAL + FreeRTOS + C；Flutter 3 / Dart 3；`flutter_test`

---

### Task 1: 固件栈快照日志格式升级

**Files:**
- Modify: `/root/develop/Packaging_machine_V1.0/APP/Src/app_monitor.c`
- Verify: `/root/develop/Packaging_machine_V1.0/APP/Inc/app_define.h`

- [ ] 定义新的日志口径，单次输出一份完整快照，至少包含 `TASK=<name> TOTAL=<words> FREE=<words>` 信息，并保留现有 `STACK_LEVEL` 兼容字段。
- [ ] 在 `app_monitor_log_stack_watermarks()` 中统一输出 7 个任务的总栈和剩余栈，避免 HMI 再从编译期宏猜测总量。
- [ ] 自查日志输出是否只依赖现有任务句柄缓存和宏，不新增跨层依赖。

### Task 2: HMI 栈快照解析与受控内存模型

**Files:**
- Create: `/root/develop/HMI/lib/features/hmi/stack_stats.dart`
- Modify: `/root/develop/HMI/lib/features/hmi/hmi_controller.dart`
- Test: `/root/develop/HMI/test/stack_stats_test.dart`

- [ ] 先写失败测试，覆盖完整快照解析、残缺快照丢弃、未知任务忽略、总览计算、内存窗口裁剪。
- [ ] 新建独立解析/模型文件，定义任务快照、总览快照和解析器，保持 UI 无协议细节。
- [ ] 在 `HmiController` 中接入新解析器，只在完整快照到齐时刷新当前栈状态。
- [ ] 给控制器增加受控内存上限：栈趋势样本有限保留、结构化快照有限保留、半截拼装状态可回收。

### Task 3: 结构化 `jsonl` 持久化与滚动写盘

**Files:**
- Modify: `/root/develop/HMI/lib/util/log_exporter_io.dart`
- Modify: `/root/develop/HMI/lib/features/hmi/hmi_controller.dart`
- Test: `/root/develop/HMI/test/stack_stats_test.dart`

- [ ] 扩展滚动写盘工具，让原始日志和栈统计结构化日志可分别写入各自文件前缀。
- [ ] 在控制器中为完整栈快照新增单独的结构化 `jsonl` 追加路径。
- [ ] 保持写盘批量刷新与滚动切文件策略，避免长时间运行单文件失控。

### Task 4: 栈统计页面改造成总览 + 表格

**Files:**
- Modify: `/root/develop/HMI/lib/features/hmi/hmi_dashboard_page.dart`
- Test: `/root/develop/HMI/test/widget_test.dart`

- [ ] 先写或补 widget 断言，确认页面出现“总栈 / 当前总已占用 / 当前总剩余 / 最危险任务”等主元素。
- [ ] 将原“栈水位统计与趋势图”页改为“总览卡片 + 任务表格”为主。
- [ ] 清空按钮改为仅清内存统计，不删除磁盘文件。
- [ ] 保证窄屏下不出现 `RenderFlex overflow`。

### Task 5: 文档与回归验证

**Files:**
- Modify: `/root/develop/HMI/doc/协议对接快速指南.md`
- Modify: `/root/develop/HMI/docs/superpowers/specs/2026-05-23-stack-stats-hmi-design.md`

- [ ] 更新协议文档，记录新的固件栈快照日志格式。
- [ ] 在设计文档补充“长期运行内存受控”约束已经落实到实现。
- [ ] 运行 `flutter test`，并在回复中明确说明固件构建是否已验证。
