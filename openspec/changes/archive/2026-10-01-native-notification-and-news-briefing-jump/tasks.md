## 1. 原生层通知与点击代理支持

- [x] 1.1 在 `macos/Runner/AppDelegate.swift` 中让 `AppDelegate` 遵守 `NSUserNotificationCenterDelegate`，配置 `delegate = self`，并在 `userNotificationCenter(_:didActivate:)` 中激活主窗口并向 Flutter 通道发送 `notificationAction`
- [x] 1.2 在 `macos/Runner/AppDelegate.swift` 中重构 `showNotification` 处理器，支持接收 `title`、`subtitle`、`body`、`actionType` 与自定义 `payload`，并通过原生 `NSUserNotification` 发送

## 2. 桥接层通用通知与动作分发

- [x] 2.1 在 `lib/services/context_services_bridge.dart` 中扩充 `showNotification` 签名（支持 `title`、`subtitle`、`body`、`actionType`、`payload`），并新增 `onNotificationAction` 回调与通道解包处理
- [x] 2.2 编写或扩充桥接层单测，验证通知动作解包与参数传递正确

## 3. 业务服务通知重构（淘汰 osascript）

- [x] 3.1 在 `lib/services/scheduled_news_service.dart` 中彻底移除 `Process.run('osascript', ...)`，改为调用 `ContextServicesBridge.instance.showNotification`（标记 `actionType: 'news'`）
- [x] 3.2 在 `lib/tools/notebook/asset_reminder_service.dart` 和 `lib/tools/ops_tool/services/ops_notifier.dart` 中同步移除 `osascript` 命令行调用，改为原生通知发送

## 4. UI 层通知点击联动（直达快报抽屉）

- [x] 4.1 在 `lib/shell/app_shell.dart` 中监听 `onNotificationAction`，当 `actionType == 'news'` 时自动切换至 `kToolIdAiAssistant`，并广播通知快报抽屉展开
- [x] 4.2 在 `lib/tools/ai_assistant/ui/ai_assistant_page.dart` 中接收展开信号，自动调用 `_openScheduledTasksDrawer` 并展示「资讯快报历史」Tab

## 5. 校验、部署与实机验收

- [x] 5.1 运行 `flutter analyze` 与全量测试套件，确认零回归
- [x] 5.2 运行 `./scripts/deploy_local.sh` 编译并部署本地应用
- [x] 5.3 实机验收：运行资讯任务触发通知，确认右上角通知显示 V8 图标与名称，点击「显示」直接唤醒 V8 并自动展开资讯快报抽屉，绝不再弹出「脚本编辑器」
