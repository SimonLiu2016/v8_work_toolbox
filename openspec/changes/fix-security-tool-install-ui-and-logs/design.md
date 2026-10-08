## Context

参见 `proposal.md`。安全工具箱中的 `ToolStatusPanel` 此前未持有安装态，且未接入实时日志流与 `LogConsole`，导致用户点击“安装”或“一键安装”时无任何界面反馈。

## Goals / Non-Goals

**Goals:**
- 在 `ToolStatusPanel` 中为单工具安装与一键批量安装提供明确的 loading 视觉状态，防重复提交。
- 遵循项目中已有的 `onLog` 契约（如 `NucleiService.scan(onLog: ...)`），将 Homebrew 的每行日志实时流式打入 `controller.log`，并在 `ToolStatusPanel` 底部以 `LogConsole` 实时呈现。
- 在批量安装时逐个更新工具就绪状态，让用户清晰感知安装进度。
- 注入 Homebrew 关键环境变量，杜绝自动更新索引阻塞与非交互式卡顿。

**Non-Goals:**
- 不重写 Homebrew 的底层安装逻辑或尝试使用其它包管理器替代。
- 不引入终端模拟器或 PTY（保持使用 `Process.start` 收集 stdout/stderr）。

## Decisions

### 1. 状态机与按钮交互
在 `_ToolStatusPanelState` 中维护：
- `String? _installingToolId`：当前正在安装/更新的工具 ID。
- `bool _installingAll`：是否处于一键批量安装状态。

当任一工具处于安装中或批量安装时：
- 对应工具行的按钮变为 `SizedBox(width: 14, height: 14, CircularProgressIndicator(strokeWidth: 2))` 与 `Text('安装中…')`，并禁用点击。
- 顶部“一键安装”按钮在 `_installingAll` 时展示为“安装中…”并禁用。

### 2. 日志流对接模式
在 `BrewInstallService.install` 中增加可选参数 `void Function(String)? onLog`：
- 在输出命令行、捕获 stdout/stderr 每一行时，调用 `onLog?.call(line)`。
- 在 `ToolStatusPanel` 中调用时，传入 `controller.log`。
- 在 `ToolStatusPanel.build()` 底部追加 `const SizedBox(height: AppTheme.space12)` 与 `LogConsole(lines: controller.logs.take(100).toList())`。

### 3. 逐个工具状态刷新
在 `_installAll` 中：
- 统计所有缺失或需更新的工具总数 `N`。
- 循环执行每个工具时，先输出 `controller.log('[${i + 1}/$N] 正在安装 ${tool.displayName}…')`。
- 每个工具安装完成后立即调用 `await controller.refreshTools()`，使列表中的徽章实时变为绿色“已就绪”，避免等几十分钟所有工具装完才统一刷新的无反馈体验。

### 4. 环境变量加固
在 `security_process_runner.dart` 的 `processEnvironment` 中增加：
- `'HOMEBREW_NO_AUTO_UPDATE': '1'`
- `'NONINTERACTIVE': '1'`
- `'HOMEBREW_NO_INSTALL_CLEANUP': '1'`（加快本地安装速度）

## Risks / Trade-offs

- [Risk] 工具可能需要 root 权限（如 `arp-scan`）或需要 macOS 命令行工具。
  → Mitigation: `BrewInstallService` 捕获完整 stderr 并输出到 `LogConsole`，并在失败时在日志控制台中提示用户手动排查。
