## Why

在实时会议翻译工具完成系统音频内录权限与 ASR 管线修复后，实机测试中发现了 3 个影响核心体验的问题：
1. **悬浮窗口缺少真实透明**：macOS 原生 NSWindow 默认 `isOpaque = true`，导致 Flutter 的半透明黑色背景叠加在系统纯黑底色上，呈现为 100% 不透明死黑，且缺少用户可调节的背景透明度档位；
2. **窗口关闭后再打开异常变形且字幕失效**：用户点击字幕窗关闭按钮后，子窗口进程调用 `windowManager.close()` 销毁了 NSWindow，二次打开时新窗口因 `desktop_multi_window` 原生通道限制抛出 `CHANNEL_LIMIT_REACHED`，导致窗口样式初始化异常中断（窗口被置于左下角、恢复为 800x600 且暴露出红黄绿三键），同时 IPC 桥接断裂导致字幕完全无法推送；
3. **全局热键切换说话人未生效**：原生热键通道与跨窗口 IPC 通道重名冲突，且在 Dart 启动初期注册时与 Swift 异步初始化存在竞态，导致 Carbon 热键实际注册失败，切换说话人始终停留在“说话人 1”。

## What Changes

- **macOS 原生级真透明与透明度调节**：
  - 在原生层提供 `styleLiveCaptionWindow` 原生窗口样式配置，显式设置 `window.isOpaque = false`、`window.backgroundColor = .clear`，并隐藏红黄绿窗口标准控制键。
  - 在 `LiveCaptionWindowApp` 悬浮窗工具栏新增透明度切换快捷按钮（如 35%、50%、70%、90% 循环切换），并持久化用户偏好。
- **悬浮窗生命周期收敛（关闭改为隐藏）**：
  - 将悬浮窗的“关闭（停止识别）”与“隐藏（识别继续）”统一收敛为 `windowManager.hide()`，避免销毁窗口实例破坏 IPC 双向配对通道。
  - 主窗口重新打开字幕窗时，优先复用已有窗口控制器执行 `show()` 与 `focus()`，秒级恢复且不触发通道限制异常。
- **全局热键通道隔离与直连注册**：
  - 将原生全局热键方法通道重命名为独立的 `'v8_work_toolbox/live_caption_hotkeys'`，彻底杜绝与 multi-window IPC 通道名冲突。
  - 在 `AppDelegate.swift` 启动时直接完成 Carbon 热键注册（⌥1/⌥2/⌥3/⌥T），消除与 Flutter 异步时序竞态。
  - 增强 `LiveTranslatorCoordinator.setActiveSpeaker`：切换说话人时，同步更新正在识别中的在途未定稿字幕段。
  - 在悬浮窗字幕流中增加醒目的说话人彩色胶囊标签（如 `[说话人 2]`），实时反馈当前说话人归属。

## Capabilities

### New Capabilities
- `live-caption-overlay`: 规范实时字幕悬浮窗真实透明度渲染、窗口生命周期收敛（关闭转隐藏以保护 IPC 机制）、以及全局热键即时切换说话人与视觉指示规范。

## Impact

- **Affected Code**:
  - `macos/Runner/AppDelegate.swift`
  - `lib/services/context_services_bridge.dart`
  - `lib/tools/live_translator/services/live_caption_hotkey_service.dart`
  - `lib/tools/live_translator/services/live_caption_bridge.dart`
  - `lib/tools/live_translator/services/live_translator_host.dart`
  - `lib/tools/live_translator/services/live_translator_coordinator.dart`
  - `lib/tools/live_translator/ui/live_caption_window.dart`
  - `lib/tools/live_translator/ui/live_translator_page.dart`
- **APIs**: 无破坏性改动，向前兼容。
- **Dependencies**: 无新增第三方依赖。
