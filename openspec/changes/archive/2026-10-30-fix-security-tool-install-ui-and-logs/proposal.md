## Why

在安全工具箱的“工具依赖”面板中，用户点击“安装”或“一键安装”按钮时界面没有任何视觉反馈（按钮不变为加载态、未展示实时日志控制台、日志流未接入 UI），导致用户误认为点击无效。同时在 macOS GUI 子进程中运行 Homebrew 安装时，未设置 `HOMEBREW_NO_AUTO_UPDATE` 等环境变量，容易静默卡在长时间的索引更新阶段。需要补齐状态机、进度反馈与实时日志控制台。

## What Changes

- 在 `ToolStatusPanel` 中增加单工具安装中（`_installingToolId`）与批量安装中（`_installingAll`）的加载状态，按钮动态呈现转圈与“安装中…”并防重复点击。
- 将 `BrewInstallService.instance.progress` 日志流与 `controller.log` 打通，并在 `ToolStatusPanel` 底部集成可折叠的 `LogConsole`，实时滚屏呈现 `brew` 执行输出。
- 在 `_installAll` 批量安装时注入实时总览进度日志（如 `[1/14] 正在安装 nmap...`），并在完成后自动重新探测与刷新状态板。
- 在 `security_process_runner.dart` 的子进程环境变量中增加 `HOMEBREW_NO_AUTO_UPDATE: '1'` 与 `NONINTERACTIVE: '1'`，避免后台交互等待与无效慢速更新。

## Capabilities

### New Capabilities
- `security/tool-dependency-manager`: 为安全工具依赖安装与批量一键安装提供状态机跟踪、防重点击反馈、实时流式安装日志展示与 LogConsole 监控。

### Modified Capabilities
<!-- 无既有已归档 specs 目录下的 capability 被修改 -->

## Impact

- 涉及文件：
  - `lib/tools/security_toolbox/ui/tool_status_panel.dart`
  - `lib/tools/security_toolbox/services/brew_install_service.dart`
  - `lib/tools/security_toolbox/services/security_process_runner.dart`
  - `test/security_toolbox_test.dart`
- 修复体验：用户点击单工具“安装”或“一键安装”后，即时看到按钮进入加载中，且底部控制台实时输出 Homebrew 输出，安装完成自动更新工具徽章。
