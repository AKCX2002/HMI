# HMI Project AGENTS

## 1. Project Identity

- 项目名称: `HMI Host`
- 角色: 作为上位机通过串口访问下位机（STM32 控制系统）
- 目标: 跨平台 Flutter 工程，统一协议层与 UI 层

## 2. Source-of-Truth Documents

- 设备与协议主文档: [doc/下位机系统说明书.md](/C:/Users/USER/Documents/dev/HMI/doc/下位机系统说明书.md)
- 协议速查: [doc/协议对接快速指南.md](/C:/Users/USER/Documents/dev/HMI/doc/协议对接快速指南.md)
- 架构说明: [doc/架构说明.md](/C:/Users/USER/Documents/dev/HMI/doc/架构说明.md)
- 界面参考: [doc/界面参考说明.md](/C:/Users/USER/Documents/dev/HMI/doc/界面参考说明.md)
- 协议关键点:
  - 20 字节固定帧
  - 请求地址 `0xAF`，响应地址 `0xBF`
  - CRC16-Modbus（低字节在前）
  - UART3 为上位机接口
- 打包机独立节点协议（来自 `Packaging_machine_V1.0`）:
  - `USART3 / RS485 / 9600 8N1`
  - 默认节点地址 `0x20`，响应主机地址 `0x00`，广播地址 `0xFF`
  - 同样使用 20 字节固定帧与 CRC16-Modbus
  - 功能码 `0x40..0x49`: 启停、状态、出袋、封口、避让、清标志、报警、心跳、版本、故障复位

## 双串口架构

```text
┌─ HMI Host ──────────────────────────────────┐
│                                              │
│  ┌─ 端口 A (USART3) ──────────────────────┐ │
│  │  主控协议 / 20B 固定帧 / CRC16-Modbus   │ │
│  │  9600 8N1 / RS485                       │ │
│  │  命令: 0x01~0x10 (上位机 -> 主控)       │ │
│  │        0x40~0x53 (上位机 -> 打包机)     │ │
│  │  仅处理 20B 主协议，不解析 DGUS         │ │
│  └──────────────────────────────────────────┘ │
│                                              │
│  ┌─ 端口 B (USART1) ──────────────────────┐ │
│  │  日志监控 + DGUS 调节协议                │ │
│  │  9600 8N1 / RS232                       │ │
│  │  DGUS 帧头 5A A5                         │ │
│  │  被动: 接收日志输出/调试信息             │ │
│  │  主动: 发送 DGUS 变参调节帧             │ │
│  │  仅处理 DGUS，不解析 20B 主协议         │ │
│  └──────────────────────────────────────────┘ │
│                                              │
│  每个端口独立配置: 串口/波特率/CRC算法       │
└──────────────────────────────────────────────┘

- 端口 A 默认 USART3 / 9600 / CRC16-Modbus
- 端口 B 默认 USART1 / 9600 / DGUS(5A A5)
- 每个端口扫描/连接/断开独立操作
- 打包机 20B 命令默认固定走端口 A；DGUS 参数/日志默认固定走端口 B；不自动跨端口回退

## 3. Confirmed Technical Baseline

- Flutter 安装路径: `C:\Users\USER\Flutter`
- 当前框架版本: `Flutter 3.41.7 / Dart 3.11.5`
- 目标平台: `Windows/macOS/Linux/Android/iOS/Web`
- 串口联调优先平台: 桌面端（Windows/Linux/macOS）
- WSL/WSLg 运行 Linux 桌面版时，若出现 `libEGL` / `MESA` / `ZINK` / `vkCreateInstance failed`，
  优先按“软件渲染 + X11 回退”口径处理：
  `GDK_BACKEND=x11 GSK_RENDERER=cairo LIBGL_ALWAYS_SOFTWARE=1 flutter run -d linux --enable-software-rendering`
- Windows 构建前置: 必须开启 Developer Mode（符号链接权限），否则插件阶段会报
  `Building with plugins requires symlink support`
- 已提供构建入口:
  - `CMakePresets.json`
  - `.vscode/tasks.json`
  - `.vscode/launch.json`

## 4. Architecture and Module Boundaries

- `lib/core/protocol`: 协议编解码、CRC 校验
- `lib/core/serial`: 串口抽象与平台实现
- `lib/features/hmi`: 业务控制器与界面

规则:

- 协议逻辑不得散落在 UI 中
- 串口原始字节解析应集中在控制器/协议层
- UI 仅做状态展示与命令触发

## 5. Workflow and Debugging Guidance

推荐流程:

1. 先阅读协议文档再改代码
2. 先做协议与串口连通性，再做界面扩展
3. 每次新增功能码时，先补协议构帧/解析，再补 UI
4. Linux/WSL 图形异常时，先检查是否误用 `root` 运行 Flutter，再切到软件渲染任务验证

联调要点:

- 固定检查帧长度是否 20
- 固定检查 CRC16 是否通过
- 非法帧不得进入业务处理路径
- Windows 构建若出现 CMake 生成器/平台冲突，先清理缓存:
  - 删除 `build/`
  - 删除 `windows/flutter/ephemeral/`
  - 再执行 `flutter pub get` 与 `flutter run -d windows`

## 6. Coding Constraints and Review Focus

- 保持跨平台单代码库，不允许业务层出现平台分叉逻辑
- 新增功能优先保证协议正确性与错误可观测性（日志/状态提示）
- 对外接口参数必须有边界保护（字节范围、空值）
- UI 约束: 必须使用响应式布局，禁止依赖固定宽高导致 `RenderFlex overflow`
  - 小屏自动切换紧凑布局（菜单/表单/日志区域）
  - 长文本必须 `ellipsis` 或换行
  - 日志区使用 `Expanded/Flexible`，不得写死高度
- 日志策略（长期追踪）:
  - 不对内存日志做固定 200 条自动清除
  - 日志输出需包含完整时间标签（`yyyy-MM-dd HH:mm:ss.SSS`）
  - 协议日志展示优先使用多行结构（时间/方向行与内容行分离），便于检索 RX/TX

## 7. Historical Pitfalls to Avoid

- 不要假设串口字节流按帧对齐到达，必须做缓冲与粘包拆包
- 打包机节点响应地址为 `0x00`，20B 接收同步不能只识别 `0xAF/0xBF`
- 不要在同一端口同时跑 DGUS 与 20B 解析，否则容易把异协议字节流误判成有效帧
- XYZ 设备测试 `target_id` 按低字节在前传输: `data[1]=low`，`data[2]=high`
- 不要在 UI 层拼接原始帧，避免维护失控
- Android 构建可能受本机 Java 版本影响，需按 Flutter 提示处理
- Windows 下最常见两类问题:
  - 符号链接未开启（Developer Mode）
  - 历史 CMake 缓存导致生成器平台不一致
- WSL 下最常见 Linux 桌面问题:
  - 以 `root` 运行 Flutter，导致工具链和图形会话权限异常
  - Wayland/Vulkan 后端不兼容，需改用软件渲染或 X11 回退

## 8. Maintenance Checklist

- 变更协议时同步更新:
  - 协议层代码
  - UI 指令入口
  - README 协议说明
- 变更构建/调试流程时同步更新:
  - `.vscode/tasks.json`
  - `.vscode/launch.json`
  - `CMakePresets.json`
  - `README.md` 的 VSCode/CMake 章节
- 变更 CI 发布流程时同步更新:
  - `.github/workflows/flutter-multi-platform.yml`
  - `README.md` 的 GitHub Actions 章节（触发规则、产物平台、Tag 规则）
- 新增稳定结论后，回写本文件，避免知识只留在聊天记录
