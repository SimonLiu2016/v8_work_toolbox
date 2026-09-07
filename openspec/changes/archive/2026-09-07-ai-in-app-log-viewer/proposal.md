## Why

当前系统中的 `AiLogger` 仅将 AI 调用的请求、响应与警告信息输出至系统标准输出/调试控制台（`debugPrint`）。对于直接使用打包桌面应用的用户或未开启终端的开发者而言，AI 调用过程处于“黑盒”状态，无法在界面上直接查看当前调用细节、重试警告或网络报错。

为了让用户在界面上直观感知 AI 调用的全流程，并在接口报错、限频（429）或调试配置时快速自查排障，需在应用内构建可视化 AI 调用日志查看器（In-App Log Viewer）。

## What Changes

- **内存日志环形缓冲与响应式流通知**：
  - 在 `AiLogger` 中维护最大 200 条的内存环形日志队列（`List<AiLogEntry>`，FIFO 淘汰）；
  - 提供 `ValueNotifier<List<AiLogEntry>>` 或响应式变更流，确保 UI 面板打开时可无感实时追加显示。
  - 支持清空日志与一键格式化复制全部日志至系统剪贴板。
- **现代化暗黑控制台风格日志弹窗 (`AiLogDialog`)**：
  - 构建居中浮层模态对话框，支持暗黑控制台风格高亮渲染；
  - 根据日志类型区分展示：🔵 Request（端点、协议、Prompt 摘要）、🟢 Response（状态码、耗时、Body 预览）、🟡 Warning（429 退避重试）、🔴 Error（调用失败详情）；
  - 提供单条日志展开查看完整报文、一键复制全部日志、清空日志等交互能力。
- **业务操作界面双入口无缝集成**：
  - **AI 基础设施配置页 (`AiConfigPage`)**：在页面顶部操作区增加「📜 查看调用日志」入口；
  - **磁盘瘦身工具页 (`SmartDiskSlimmerPage`)**：在「🤖 AI 批量诊断」按钮旁增加「📜 AI 日志」快捷入口。

## Capabilities

### Modified Capabilities
- `ai-configuration`: 增加应用内 AI 交互实时可观测性与日志查看器能力，允许用户在图形界面查看最近的 AI 请求/响应/警告明细，并支持一键复制与清空。

## Impact

- **`lib/services/ai_logger.dart`**：扩展 `AiLogEntry` 数据结构、内存缓冲队列与 UI 监听通知。
- **`lib/shell/ai_log_dialog.dart`**：新建日志查看器对话框组件。
- **`lib/shell/ai_config_page.dart`**：在顶部操作栏集成「查看调用日志」按钮。
- **`lib/tools/slimmer/smart_disk_slimmer_page.dart`**：在批量诊断操作栏集成「AI 日志」按钮。
- **`test/ai_log_viewer_test.dart`**：单元与 Widget 测试覆盖日志缓冲、淘汰机制与弹窗交互。
