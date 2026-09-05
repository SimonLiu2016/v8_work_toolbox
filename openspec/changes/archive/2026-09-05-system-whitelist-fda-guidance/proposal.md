## Why

在前期磁盘瘦身工具的真实系统测试中，暴露出三类影响可用性、准确性与代码健康的问题：
1. **静态分析警告未清零**：`lib/tools/slimmer/ai_disk_diagnostics_service.dart` 存在未引用的 `_parseJsonArray`，导致 CI/Analyzer 产生 Warning；
2. **系统基础服务与 CLI 开发者工具误报**：macOS 原生服务（`AddressBook`, `GeoServices`, `CoreTelephony` 等）以及常用命令行开发工具（`Homebrew`, `rtk`, `claude-cli-nodejs`, `mysql`, `ms-playwright`, `tabnine` 等）因无独立 `/Applications/*.app` 包体，被误当作"孤立应用残留"列出；
3. **FDA (完全磁盘访问权限) 与 AI 引导缺失**：当 macOS 沙盒受限导致某些库目录无权限读取时缺乏直观的引导弹窗；当未配置 AI API Key 时点击"让 AI 分析"缺乏一键前往配置的闭环交互。

## What Changes

- **消除静态分析 Warning**：
  - 移除 `AiDiskDiagnosticsService` 中的废弃私有方法 `_parseJsonArray`，使 `flutter analyze --no-fatal-infos` 达到 0 错误 0 告警。
- **系统核心服务与 CLI 工具白名单**：
  - 在 `AppOrphanDetector` 中扩充 macOS 原生无 `com.apple.` 前缀的系统目录豁免表（`addressbook`, `geoservices`, `coretelephony`, `clouddocs`, `mobilesync`, `callhistory*` 等）；
  - 建立常见开发者 CLI 工具与后台服务豁免表（`homebrew`, `rtk`, `claude-cli-nodejs`, `mysql`, `ms-playwright`, `docker desktop`, `tabnine` 等），避免误报。
- **完全磁盘访问权限 (FDA) 状态感知与引导**：
  - 在扫描过程中捕获 `FileSystemException (EPERM / Operation not permitted)` 标志；
  - 若权限受限，在瘦身页顶部显示轻量警示横幅，并提供"打开系统设置授权"快捷按钮（通过 URL Scheme `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles` 一键直达）。
- **AI 未配置时的友好引导**：
  - 用户触发 AI 研判时先检查活跃 Provider；若未配置，弹出引导对话框并提供"立即配置 AI"按钮跳转至配置页。

## Capabilities

### New Capabilities

### Modified Capabilities
- `orphan-detection-accuracy`: 补充 macOS 系统原生非 `com.apple.` 基础服务与常见终端 CLI 开发者工具白名单，彻底杜绝误报。
- `disk-analyzer`: 增加完全磁盘访问权限 (FDA) 状态检测引导横幅与 AI 未配置时的友好跳转引导。

## Impact

- `lib/tools/slimmer/ai_disk_diagnostics_service.dart`
- `lib/tools/slimmer/app_orphan_detector.dart`
- `lib/tools/slimmer/disk_scanner_service.dart`
- `lib/tools/slimmer/smart_disk_slimmer_page.dart`
