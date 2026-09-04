## Why

Smart Disk Slimmer 工具存在五个影响可用性与安全性的问题：扫描时 UI 完全卡住（鼠标转圈）、复选框无法手动操作、JetBrains 同名条目无法区分、以及多个正在使用的应用（如 VS Code、bilibili）被误判为"安全清理"。误判的根因是孤立残留检测仅依赖精确名称匹配，而 macOS 的 Application Support 目录名与 .app 包名之间没有强制关联——这是一个系统性缺陷，不止影响个别应用。

## What Changes

- **异步扫描**：将 `_calcDirSize`、`_measureDirQuick`、`_quickDirSize` 中的 `listSync()` 改为异步实现，定期 yield 控制权给 Flutter 框架，消除扫描期间的 UI 卡顿。
- **复选框修复**：将 Stream yield 的 `List.unmodifiable` 改为可修改列表，使用户能手动勾选/取消清理项。
- **JetBrains 条目区分**：在标题或副标题中标注目录来源（配置 vs 缓存），消除同名歧义。
- **多层防误判检测**：重构 `AppOrphanDetector`，引入四层递进验证——Bundle ID 精确匹配、已知别名映射 + 子串双向匹配、最近修改时间降级、用户反馈闭环。默认策略从"安全清理"改为"谨慎确认"。
- **用户标记持久化**：当用户手动取消勾选被标记为"安全清理"的项目时，记录该决策到配置文件，下次扫描自动应用。

## Capabilities

### New Capabilities

- `disk-scanner-async`: 异步磁盘扫描能力——扫描过程不阻塞 UI，支持进度实时更新与取消操作
- `orphan-detection-accuracy`: 孤立残留精准检测——多信号源交叉验证（Bundle ID、别名映射、子串匹配、修改时间），不确定时默认标记为"谨慎确认"

### Modified Capabilities

- `disk-analyzer`: 修正复选框交互（List.unmodifiable → 可修改列表）、JetBrains 条目来源标识、用户标记持久化与反馈闭环

## Impact

- `lib/tools/slimmer/disk_scanner_service.dart` — `_calcDirSize` 改为异步，Stream yield 改为可修改列表
- `lib/tools/slimmer/multi_version_scanner.dart` — `_quickDirSize` 改为异步，JetBrains 标题增加目录来源标识
- `lib/tools/slimmer/app_orphan_detector.dart` — 重构检测逻辑，增加 Bundle ID 读取、别名映射、子串匹配、修改时间降级
- `lib/tools/slimmer/smart_disk_slimmer_page.dart` — 复选框交互修复，用户取消勾选时触发持久化
- `lib/tools/slimmer/slimmer_models.dart` — 可能需要增加用户标记相关字段
- `lib/services/settings_store.dart` — 增加用户清理偏好持久化
