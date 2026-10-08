## Why

在安全工具箱的实际使用过程中：
1. **NetExec 安装失败与无法识别**：NetExec 未在 PyPI 发布同名预编译包，直接执行 `pipx install netexec` 会报 404 错误，官方推荐走 `git+https://github.com/Pennyw0rth/NetExec`；此外，macOS GUI 进程未将 `$HOME/.local/bin` 纳入 PATH，导致 pipx 安装的二进制无法被识别；版本参数错误（`-V` 而非 `--version`）也会导致探测失败。
2. **控制台日志不可复制**：`LogConsole` 使用纯 `Text` 组件且未包裹可划词选择的 `SelectionArea`，且缺乏顶部“一键复制全部日志”操作，用户在排查失败时无法方便地提取并拷贝日志信息。

## What Changes

- **PATH 目录扩展**：
  - 在 `SecurityProcessRunner` 的 `augmentedPath` 与 `resolveExecutable` 中加入用户目录 `$HOME/.local/bin` 与 `$HOME/bin`，支持发现 pipx 与用户级 CLI 二进制。
- **NetExec 专属安装与版本探测修正**：
  - 将 `netexec` 的 pipx 安装源由包名改为官方源码库地址 `git+https://github.com/Pennyw0rth/NetExec`。
  - 将 `netexec` 的 `versionArg` 由 `-V` 修正为 `--version`。
- **控制台日志交互增强**：
  - 在 `LogConsole` 顶部增加控制台工具栏，显示日志行数与“复制全部”按钮，点击后将完整日志复制到系统剪贴板并提示反馈。
  - 将日志文本列表包裹在 `SelectionArea` 中，支持鼠标自由拖拽划词选中和 `Cmd+C` 快捷复制。

## Capabilities

### New Capabilities
- `security/tool-dependency-manager`: 安全工具依赖安装流程与渠道策略管理。

### Modified Capabilities
<!-- 无已有 spec 变更 -->

## Impact

- `lib/tools/security_toolbox/services/security_process_runner.dart`：在 PATH 解析与子进程环境变量中注入 `$HOME/.local/bin`。
- `lib/tools/security_toolbox/services/security_tool_registry.dart`：修正 `netexec` 的 `versionArg` 与 `pipxPackage` 参数。
- `lib/tools/security_toolbox/services/brew_install_service.dart`：针对 pipx 支持特定 git/package 映射源。
- `lib/tools/security_toolbox/ui/widgets.dart`：重构 `LogConsole`，增加 `SelectionArea`、行数统计与“复制全部”按钮。
