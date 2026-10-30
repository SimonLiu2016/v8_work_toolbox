## Why

在 macOS 实时会议翻译悬浮窗中，用户点击“调节透明度”按钮时，数值虽在切换，但实际视觉仍为死黑非透明；同时“开始/停止记录”按钮点击后，图标与提示文本始终固定不变，无法直观反映当前录制状态。本变更旨在打通真实窗口级透明度驱动链路，并为悬浮窗记录按钮注入响应式状态反馈。

## What Changes

- **主进程打开字幕窗时调用原生样式配置**：在 `LiveTranslatorHost.openCaptionWindow()` 中主进程直连调用 `ContextServicesBridge.instance.styleLiveCaptionWindow()`，确保 macOS 原生 `NSWindow` 正确移除死黑背景并置顶。
- **窗口管理器级透明度联动**：在 `LiveCaptionWindowApp` 中调节透明度时，调用 `windowManager.setOpacity(_opacity)` 直接改变 macOS 窗口级 `alphaValue`，实现立竿见影的真实半透明与穿透效果。
- **悬浮窗记录状态响应与视觉反馈**：在 `LiveCaptionWindowApp._applyState()` 中提取并监听 `isRecording` 字段；根据记录状态动态切换记录按钮图标（`Icons.stop_circle` / `Icons.radio_button_unchecked`）、颜色及 Tooltip 提示。

## Capabilities

### New Capabilities

- `live-caption-overlay`: 实时字幕悬浮窗真实窗口透明度驱动与多状态记录指示反馈规范。

## Impact

- `lib/tools/live_translator/services/live_translator_host.dart`: 在打开与复用字幕窗口时触发原生样式配置。
- `lib/tools/live_translator/ui/live_caption_window.dart`: 联动 `windowManager.setOpacity` 并渲染响应式录制状态。
