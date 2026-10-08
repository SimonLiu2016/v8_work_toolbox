## Context

在解决安装渠道与日志展示问题时发现：
1. `netexec` 在 PyPI 上无包，需指定 `git+https://github.com/Pennyw0rth/NetExec` 安装；且其版本参数必须是 `--version`。
2. pipx 安装的可执行文件落在 `$HOME/.local/bin`，但在 macOS LaunchServices/GUI 进程中，PATH 缺少该路径，导致 `resolveExecutable` 判定为未安装。
3. `LogConsole` 未包裹 `SelectionArea`，日志文本无法复制。

## Goals / Non-Goals

**Goals:**
- 在 `augmentedPath` 与 `resolveExecutable` 中加入 `$HOME/.local/bin` 与 `$HOME/bin`。
- 在 `SecurityTool` 中支持配置 `pipxPackage`（当与可执行文件名不一致时使用），并将 NetExec 的安装包指向官方 git 仓库，版本参数修正为 `--version`。
- 升级 `LogConsole`，增加 `SelectionArea` 支持自由选择，增加顶部工具栏提供“复制全部”功能。

**Non-Goals:**
- 不修改除安全工具模块外的其他通用控件。

## Decisions

### 1. PATH 搜索路径加入用户目录
在 `security_process_runner.dart` 中读取 `Platform.environment['HOME']`，若非空则加入：
`$home/.local/bin`, `$home/bin`。
这样能统一覆盖 pipx、cargo、本地手动放置等工具。

### 2. LogConsole 增强
在 `widgets.dart` 的 `LogConsole` 中：
- 顶部放置 Header Row：左侧为控制台标题与行数徽标，右侧为“复制全部”小按钮。
- 下方文本内容包裹在 `SelectionArea` 中，便于直接划选。
- 点击“复制全部”调用 `Clipboard.setData(ClipboardData(text: lines.join('\n')))`，并给出明确反馈。

## Risks / Trade-offs

- 无破坏性风险，所有既有单元测试与工具调用均保持兼容。
