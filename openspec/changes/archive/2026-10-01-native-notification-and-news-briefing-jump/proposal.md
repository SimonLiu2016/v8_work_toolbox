## Why

「AI资讯与检索助手」在执行定时任务查到新鲜资讯后，通过命令行 `osascript -e 'display notification ...'` 弹出系统提醒。这导致 macOS 将通知归属权绑定给 `osascript`（即「脚本编辑器.app」）。用户点击通知或点击「显示」按钮时，系统会错误唤起一个空白的「脚本编辑器」窗口，而 V8 宿主应用毫无响应，资讯快报也未能呈现给用户。

通知应当由应用自身（`NSUserNotificationCenter`）以原生方式送达，且点击通知时应激活宿主应用并直达对应的「资讯快报」界面。

## What Changes

- **统一 macOS 原生通知通道（淘汰 `osascript` 唤起）**：
  - 在 `ContextServicesBridge` 中扩充通用的原生通知发送能力（支持 `title`、`subtitle`、`body` 与自定义动作元数据 `action`、`payload`）。
  - 在 macOS 原生层 `AppDelegate.swift` 中统一通过 `NSUserNotificationCenter` 发送通知，确保应用图标与归属权正确绑定为 V8 工作工具箱。
  - 将 `ScheduledNewsService`（以及同类的 `AssetReminderService`、`OpsNotifier`）迁移至该原生通道。
- **通知点击激活与路由跳转联动**：
  - 在 `AppDelegate.swift` 中实现 `NSUserNotificationCenterDelegate` 的 `userNotificationCenter(_:didActivate:)` 回调。
  - 用户点击通知或点击「显示」按钮时，原生层将应用激活置顶（`showMainWindow()`），并通过 `contextServicesChannel` 向 Flutter 层分发激活事件。
  - Flutter 层（`AppShell` 与 `AiAssistantPage`）监听到资讯通知激活事件后，自动将主界面切换至「AI资讯与检索」工具，并自动滑出「资讯快报历史」抽屉（展示最新快报），实现点击直达。

## Capabilities

### New Capabilities
- `desktop-native-notifications`: 统一的 macOS 原生桌面通知与点击交互机制，支持携带动作载荷，并在用户点击通知时激活主应用并分发事件。

### Modified Capabilities
- `ai-news-assistant`: 定时任务快报提醒改由原生桌面通知通道送达，且用户点击通知后直达 AI 助手并展示快报历史抽屉。

## Impact

- **原生层**：`macos/Runner/AppDelegate.swift` 接入 `NSUserNotificationCenterDelegate`，处理通知展示与激活回调。
- **服务通道**：`lib/services/context_services_bridge.dart` 扩充通知发送与接收通知点击动作的回调。
- **业务服务**：`lib/services/scheduled_news_service.dart` 替换 `osascript` 调用；附带治理 `lib/tools/notebook/asset_reminder_service.dart` 与 `lib/tools/ops_tool/services/ops_notifier.dart`。
- **UI 交互**：`lib/shell/app_shell.dart` 响应通知路由跳转；`lib/tools/ai_assistant/ui/ai_assistant_page.dart` 提供打开快报历史抽屉的静态/状态控制。
