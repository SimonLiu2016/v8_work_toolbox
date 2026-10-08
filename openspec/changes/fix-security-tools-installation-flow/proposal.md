## Why

在安全工具依赖管理面板中，用户点击单项“安装”或顶部“一键安装”时遭遇高失败率与误导性反馈：
1. 批量安装完成时，日志输出 `成功安装 0/9 个工具`，文本模板因包含“成功安装”与“9 个工具”容易使用户误以为已全部安装成功；
2. 部分受管工具（如 `netexec` 在官方 Homebrew 核心源中无 formula，`metasploit` 因 Gatekeeper 校验在 macOS cask 中被禁用）无法通过 `brew install` 成功拉取，导致单项安装必定以 exit code 1 失败；
3. 在 Intel macOS（Homebrew Tier 3）环境下，安装带依赖的工具（如 `sqlmap` 触发依赖升级）会弹出 `[y/n]` 交互确认；由于子进程未重定向关闭标准输入，导致进程悬挂或因输入空缺异常终止；
4. 耗时较大的编译型工具（如 `httpx`、`ffuf` 无 x86_64 bottle 需本地 Go 编译，`exploitdb` 需拉取 1GB 仓库）缺乏耗时预估与分步状态展示，且并发下载锁超时机制未与用户交互良好配合。

本变更旨在改进受管工具安装策略与执行流程，区分工具来源渠道，加固子进程非交互执行，消除误导性日志并提供清晰诊断。

## What Changes

- **日志与统计反馈精确化**：
  - 批量安装结果按成功与失败分类展示（如 `批量安装结束：0 个成功，9 个失败`），并在存在失败时明确告警与指引。
  - 在单工具安装失败时，高亮提取关键错误信息（如包名不存在、下载锁冲突、依赖更新阻断等）并打印到日志控制台。
- **工具渠道与安装策略解耦**：
  - 对 `netexec` 识别支持渠道：优先检测 `pipx`，若存在则使用 `pipx install netexec`，若无则在界面清晰提示安装指令。
  - 对 `metasploit` 标记为独立/手动安装工具，提供 Rapid7 官方安装引导，禁用盲目的 `brew install metasploit`。
- **子进程管道加固**：
  - 针对 Homebrew 安装命令彻底关闭 stdin 并重定向 EOF（防止因 `[y/n]` 依赖升级确认挂起）。
  - 支持智能检测 Homebrew 锁冲突，若检测到后台锁未释放，给出针对性提示。
- **长耗时编译型工具提示**：
  - 针对需要本地编译（如 `httpx`、`ffuf`）或大仓库拉取（`exploitdb`）的工具，在启动安装时输出预估耗时提示，避免用户误判卡死。

## Capabilities

### New Capabilities
- `security/tool-dependency-manager`: 安全工具依赖安装流程与渠道策略管理。

### Modified Capabilities
<!-- 无已有 spec 变更 -->

## Impact

- `lib/tools/security_toolbox/services/security_tool_registry.dart`：增加工具安装渠道分类（brew / pipx / manual / source）与安装提示。
- `lib/tools/security_toolbox/services/brew_install_service.dart`：加固进程 stdin 交互处理、错误日志提取、批量安装日志文案优化及多渠道支持。
- `lib/tools/security_toolbox/ui/tool_status_panel.dart`：优化手动安装/外部渠道工具的 UI 呈现与安装按钮状态。
