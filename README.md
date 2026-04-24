# HMI Host (Flutter)

面向自动出货打包机的上位机工程。  
本项目使用 Flutter 单代码库覆盖 `Windows / macOS / Linux / Android / iOS / Web`，并在桌面端提供串口通信能力。

## 0. 文档导航

- 项目协作约束: [AGENTS.md](/C:/Users/USER/Documents/dev/HMI/AGENTS.md)
- 协作规范: [CONTRIBUTING.md](/C:/Users/USER/Documents/dev/HMI/CONTRIBUTING.md)
- 变更记录: [CHANGELOG.md](/C:/Users/USER/Documents/dev/HMI/CHANGELOG.md)
- 架构说明: [doc/架构说明.md](/C:/Users/USER/Documents/dev/HMI/doc/架构说明.md)
- 协议快速指南: [doc/协议对接快速指南.md](/C:/Users/USER/Documents/dev/HMI/doc/协议对接快速指南.md)
- UI 参考说明: [doc/界面参考说明.md](/C:/Users/USER/Documents/dev/HMI/doc/界面参考说明.md)
- 下位机源文档: [doc/下位机系统说明书.md](/C:/Users/USER/Documents/dev/HMI/doc/下位机系统说明书.md)

## 1. 环境确认

- Flutter 安装路径: `C:\Users\USER\Flutter`
- 当前版本: `Flutter 3.41.7` / `Dart 3.11.5`

## 2. 已实现内容

- Flutter 多平台工程骨架
- 串口连接管理（端口扫描、连接、断开、收发）
- 协议层:
  - 固定 20 字节帧
  - 地址字节 `0xAF/0xBF`
  - `CRC16-Modbus` 校验
- 常用指令快捷发送:
  - `0x10` 初始化查询
  - `0x09` 状态查询
  - `0x07` 取货开锁
  - `0x01` 订单下发
- 通信日志面板（TX/RX 帧可视化）

## 3. 运行方式

```bash
flutter pub get
flutter run -d windows
```

示例:

```bash
flutter run -d windows --release
```

## 4. 代码结构

```text
lib/
  main.dart
  core/
    protocol/
      crc16_modbus.dart
      hmi_frame.dart
    serial/
      serial_transport.dart
      serial_transport_impl.dart
  features/
    hmi/
      hmi_controller.dart
      hmi_dashboard_page.dart
doc/
  下位机系统说明书.md
```

## 5. 协议说明（与下位机文档一致）

- 帧长: `20 bytes`
- 请求地址: `0xAF`
- 响应地址: `0xBF`
- 帧结构:
  - `byte0`: addr
  - `byte1`: func
  - `byte2~17`: data[16]
  - `byte18~19`: CRC16 (低字节在前)

## 6. 注意事项

- Web 端无法直接访问本地串口硬件，建议桌面端用于联调。
- Android 构建提示当前 Java 版本偏高（`26.0.1`），如需 Android 构建请按 Flutter 提示切换到 Java 17~24。

## 7. 开发验证

```bash
dart analyze
flutter test
```

## 8. VSCode 与 CMake 工作流

- 已提供:
  - `.vscode/launch.json`
  - `.vscode/tasks.json`
  - `CMakePresets.json`
- 常用任务:
  - `Windows: Enable Developer Mode (open settings)`
  - `Flutter: run windows`
  - `Flutter: build windows debug`
  - `CMake: Configure+Build (debug)`

### 8.1 必须先启用符号链接

若提示 `Building with plugins requires symlink support`，先启用 Windows 开发者模式:

```powershell
start ms-settings:developers
```

启用后执行:

```powershell
flutter clean
flutter pub get
flutter run -d windows
```
