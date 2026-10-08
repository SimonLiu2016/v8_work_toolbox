# 提案：修复 Nuclei 漏洞扫描执行与控制台日志输出流

## Why

在安全工具箱的「漏洞扫描」界面中，用户点击「开始 nuclei 扫描」后，控制台无任何输出，看不到软件运行的记录。经过排查，发现当前实现存在三处阻塞：
1. **参数分类映射错误导致引擎启动崩溃**：`NucleiCategory` 的 key（如 `cves`, `exposures` 等）被直接当做 `-t <key>` 传递，而在 Nuclei v3+ 的模板库中无对应根目录，导致 Nuclei 启动即抛出致命错误 `[FTL] Could not run nuclei: no templates provided for scan` 并闪退；
2. **静默标志屏蔽了所有状态进度**：启用了 `-silent`，导致 Nuclei 仅在命中漏洞时输出 JSON，屏蔽了模板装载、目标装载及探测进度；
3. **控制台前端截断 Bug**：`LogConsole` 渲染时调用 `controller.logs.take(60)`，错误地截取了列表前 60 条最早的历史日志，导致执行扫描时新增的所有实时日志完全被丢弃。

## What Changes

- **Nuclei 模板分类改用 Tag 驱动与路径适配**：重构 `NucleiCategory` 映射机制，将其映射为标准的 Nuclei Tags（如 `cves` -> `cve`，`exposures` -> `exposure`，`misconfiguration` -> `misconfig`，`defaultLogins` -> `default-login`，`technologies` -> `tech`，`network` -> `network`），并通过 `-tags` 传递，确保跨协议、跨资产类型 100% 成功加载模板。
- **开放 Nuclei 运行状态输出并捕获退出码**：移除 `-silent`，保留 `-jsonl -no-color`。使 Nuclei 的模板统计、目标统计及扫描信息可实时通过 `onLog` 反馈到界面，并在异常退出时输出明确的错误提示。
- **修复前端控制台最新日志切片**：修正各视图（`vuln_scan_view`, `web_recon_view`, `lan_recon_view`, `tool_status_panel`）中对 `controller.logs` 的切片逻辑，保证展示的是**最新的日志尾部**（如最新 100 行），彻底解决日志不更新的假死现象。
- **增强控制台交互**：为 `LogConsole` 增加自动向下滚底与一键「清空日志」快捷功能，让运行状态一目了然。

## Capabilities

### New Capabilities
- `security/vuln-scan-and-console`: 覆盖漏洞扫描引擎参数构建（Tag 过滤与模板解析）、Nuclei 实时执行流式反馈，以及安全控制台最新日志滑动窗口与滚底交互。

### Modified Capabilities
<!-- 无既有 spec 需求变更 -->

## Impact

- `lib/tools/security_toolbox/services/vuln_scan_services.dart`: 改造 `NucleiCategory` 与 `NucleiService.scan` 参数生成逻辑，移除 `-silent`，强化 stderr 与异常退出日志。
- `lib/tools/security_toolbox/services/security_session_controller.dart`: 增加 `recentLogs([int count = 100])` 辅助方法。
- `lib/tools/security_toolbox/ui/vuln_scan_view.dart`: 修复传给 `LogConsole` 的日志数据流。
- `lib/tools/security_toolbox/ui/web_recon_view.dart`, `lan_recon_view.dart`, `tool_status_panel.dart`: 统一修复 `logs.take(...)` 截断错误。
- `lib/tools/security_toolbox/ui/widgets.dart`: 增强 `LogConsole`，支持清空日志与自动滚动。
