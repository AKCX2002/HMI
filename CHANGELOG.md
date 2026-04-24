# Changelog

All notable changes to this project will be documented in this file.

## [0.1.0] - 2026-04-24

### Added

- 初始 Flutter 多平台工程骨架
- 串口传输抽象与 `flutter_libserialport` 实现
- UART3 协议帧编解码（20B 固定帧 + CRC16-Modbus）
- HMI 控制台首版 UI（连接、指令、日志）
- 关键指令快捷入口: `0x01/0x07/0x09/0x10`
- 项目级协作说明 `AGENTS.md`
- 开源协作文档 `CONTRIBUTING.md`
- 协议与架构文档（`doc/`）

### Changed

- 补充公开 API 的 DartDoc 注释
- README 增加文档导航与开发说明
