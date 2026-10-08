## Context

「AI资讯与检索助手」在执行定时任务查到新鲜资讯后，通过命令行 `osascript -e 'display notification ...'` 弹出系统提醒。这导致 macOS 将通知归属权绑定给 `osascript`（即「脚本编辑器.app」）。用户点击通知或点击「显示」按钮时，系统会错误唤起一个空白的「脚本编辑器」窗口，而 V8 宿主应用毫无响应，资讯快报也未能呈现给用户。

类似的问题也存在于 `AssetReminderService` 和 `OpsNotifier` 中。

## Goals / Non-Goals

**Goals:**
- 将所有通过 `osascript` 发出的系统通知彻底替换为 V8 原生通知（`NSUserNotificationCenter`），确保应用图标与名称正规归属。
- 实现 `NSUserNotificationCenterDelegate` 的通知点击激活机制（`userNotificationCenter(_:didActivate:)`）。
- 点击资讯通知横幅或「显示」按钮时：
  1. 唤起并置顶 V8 工作工具箱主窗口；
  2. 自动切换到「AI资讯与检索助手」；
  3. 自动滑出「定时资讯快报历史」抽屉，直接呈现最新简报。
- 统一重构 `ContextServicesBridge.showNotification` 为通用通知下发接口，覆盖资讯提醒、笔记保存、资产提醒与运维告警。

**Non-Goals:**
- 不引入第三方通知外部包（继续使用 macOS 原生能力，零新依赖）。
- 不重构快报内容生成的现有业务流程。

## Decisions

### Decision 1: 原生层统一下发与代理接入

- **选择**：
  - 在 `AppDelegate.swift` 中让 `AppDelegate` 遵守 `NSUserNotificationCenterDelegate`，并在启动时设置 `NSUserNotificationCenter.default.delegate = self`。
  - 实现 `userNotificationCenter(_:shouldPresent:) -> true`，保证应用在前台或后台均能弹出横幅。
  - 实现 `userNotificationCenter(_:didActivate:)`，当用户点击通知（`activationType == .contentsClicked || .actionButtonClicked`）时：
    1. 调用 `self.showMainWindow()` 唤起并前置窗口；
    2. 读取 `notification.userInfo`，通过 `contextServicesChannel?.invokeMethod("notificationAction", arguments: userInfo)` 转发给 Flutter。

### Decision 2: 泛化 `ContextServicesBridge.showNotification`

- **选择**：
  - 将 `ContextServicesBridge.instance.showNotification` 签名从专用的 `{title, notebook}` 扩展为通用形式：
    ```dart
    Future<void> showNotification({
      required String title,
      String? subtitle,
      required String body,
      String? actionType, // 如 'news', 'note', 'asset', 'ops'
      Map<String, dynamic>? payload,
    });
    ```
  - 增加激活回调：`void Function(String actionType, Map<String, dynamic> payload)? onNotificationAction;`。

### Decision 3: 路由联动与抽屉直达

- **选择**：
  - 在 `AppShell` 或全局事件流中监听 `onNotificationAction`。
  - 当 `actionType == 'news'` 时：
    1. 调用 `selectTool(kToolIdAiAssistant)` 切换到「AI 资讯与检索助手」；
    2. 通过事件通知或静态方法触发 `AiAssistantPage` 打开 `ScheduledTasksDrawer` 并切到第 1 个 Tab（快报历史）。

### Decision 4: 淘汰项目内全部 `osascript` 通知

- **选择**：
  - 同步重构 `ScheduledNewsService._dispatchMacNotification`、`AssetReminderService._dispatchMacNotification` 与 `OpsNotifier.showNotification`，统一调用 `ContextServicesBridge.instance.showNotification`，从根源上杜绝「脚本编辑器」意外弹出的任何可能性。

## Risks / Trade-offs

- **[Risk] 用户点击通知时主窗口已最小化或关闭** → Mitigation: `AppDelegate.didActivate` 会调用 `showMainWindow()`，恢复 window 的 frame 并执行 `makeKeyAndOrderFront` + `activate`，确保稳定置顶。
- **[Risk] Flutter 尚未准备好即收到点击** → Mitigation: 通道初始化在 Flutter 引擎就绪后才建立，并在收到通知事件后通过微任务队列安全调用 `AppShell.selectTool`。
