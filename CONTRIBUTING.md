# Contributing Guide

感谢参与 `HMI Host` 项目。

## 1. 分支与提交建议

- 分支命名建议: `feature/<topic>`、`fix/<topic>`、`docs/<topic>`
- 提交信息建议采用 Conventional Commits:
  - `feat:`
  - `fix:`
  - `docs:`
  - `refactor:`
  - `test:`
  - `chore:`

示例:

```text
feat(protocol): add 0x03 pack-seal command builder
fix(serial): recover parser after crc mismatch
docs(readme): update protocol integration steps
```

## 2. 代码规范

- 遵循项目 `analysis_options.yaml`
- 新增公开 API 需补 DartDoc 注释
- 协议逻辑放在 `lib/core/protocol`
- 串口逻辑放在 `lib/core/serial`
- UI 仅负责展示与交互，不直接拼接原始帧

## 3. 文档规范

- 行为或协议变更时，至少同步以下文档:
  - `README.md`
  - `doc/协议对接快速指南.md`
  - `AGENTS.md`（若结论稳定且对协作有长期价值）

## 4. 提交流程

1. `flutter pub get`
2. `dart analyze`
3. `flutter test`
4. 自测关键流程（串口连接、发送指令、日志显示）
5. 提交变更

## 5. 评审重点

- 协议兼容性（20 字节帧、CRC、地址与功能码）
- 异常路径可观测性（日志、错误状态）
- 跨平台影响（桌面与移动端差异）
