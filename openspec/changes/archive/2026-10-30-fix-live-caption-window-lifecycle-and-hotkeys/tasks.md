## 1. macOS 原生悬浮窗样式与通道隔离配置

- [x] 1.1 在 `macos/Runner/AppDelegate.swift` 中实现 `configureLiveCaptionWindow()`，设置 `isOpaque = false`、`backgroundColor = .clear` 并隐藏原生三色交通灯按钮
- [x] 1.2 在 `macos/Runner/AppDelegate.swift` 中将热键通道重命名为 `'v8_work_toolbox/live_caption_hotkeys'`，并在 `applicationDidFinishLaunching` 阶段直连调用 `registerLiveCaptionHotKeys()`
- [x] 1.3 在 `lib/services/context_services_bridge.dart` 中新增 `styleLiveCaptionWindow()` 方法并连通原生通道

## 2. 悬浮窗生命周期收敛与防崩溃治理

- [x] 2.1 修改 `lib/tools/live_translator/services/live_translator_host.dart` 的 `closeCaptionWindow` 和 `openCaptionWindow`：关闭时仅隐藏子窗口，重新打开时复用已有控制器执行 `show()` 与 `focus()`
- [x] 2.2 修改 `lib/tools/live_translator/ui/live_caption_window.dart` 的关闭按钮逻辑，收敛为 `windowManager.hide()`，彻底杜绝破坏跨窗口 IPC 配对
- [x] 2.3 在 `LiveCaptionWindowApp._initWindow` 中将 `setSize` 调整到通信初始化之前，并调用 `styleLiveCaptionWindow()` 注入透明样式与置顶特性

## 3. 悬浮窗透明度调节与说话人视觉反馈

- [x] 3.1 在 `lib/tools/live_translator/ui/live_caption_window.dart` 工具栏增加透明度调节按钮（35%、50%、70%、90% 循环切换），并读写持久化配置
- [x] 3.2 在 `lib/tools/live_translator/services/live_caption_hotkey_service.dart` 中将通信通道迁移至专用 `'v8_work_toolbox/live_caption_hotkeys'`
- [x] 3.3 修改 `lib/tools/live_translator/services/live_translator_coordinator.dart`，在 `setActiveSpeaker` 时同步更新当前在途未定稿字幕段的说话人槽位
- [x] 3.4 在 `lib/tools/live_translator/ui/live_caption_window.dart` 字幕列表中为每条字幕增加彩色说话人胶囊徽章（如 `[说话人 1]`）

## 4. 单元测试与部署验证

- [x] 4.1 运行 `flutter test test/live_translator_test.dart` 与 `flutter analyze` 确保无代码分析与回归错误
- [x] 4.2 执行 `./scripts/deploy_local.sh` 编译 Release、重签名 entitlements 并部署替换本机应用 `/Applications/V8WorkToolbox.app`
