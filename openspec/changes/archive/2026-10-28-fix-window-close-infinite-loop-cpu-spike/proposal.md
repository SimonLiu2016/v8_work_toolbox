## Why

应用在空闲状态或窗口触发关闭/失焦动作后，主线程持续占用 100%+ CPU 资源且永不休眠（实测空转耗时超过 150 分钟），导致设备严重发热发烫并消耗电量。
经底层采样与符号反查定位，该问题的根本原因是 `window_manager` macOS 插件的 `close()` 实现（`mainWindow.performClose(nil)`）与 Dart 侧 `onWindowClose()` 回调之间缺乏重入保护，形成了「原生发事件 -> Dart 处理 -> Dart 调 close -> 原生再发事件」的无限事件递归循环；同时部分子窗口误用全局 `windowManager.close()`，波及并激活了主窗口的监听循环。

## What Changes

1. **切断窗口关闭事件无限递归风暴**：
   - 在 `StudioShellPage` (`_StudioShellPageState`) 中增加 `_isClosing` 状态自锁；
   - 在执行真正的窗口关闭前，必须先调用 `windowManager.removeListener(this)` 移除监听并解除 `setPreventClose(false)`，彻底避免 AppKit `performClose` 级联触发二次 `onWindowClose`。
2. **规范子窗口关闭与失焦行为**：
   - 修复 `LookupWindow` (`_LookupPanelViewState`) 在失焦 `onWindowBlur` 及点击关闭 `_onClose` 时调用全局 `windowManager.close()` 的缺陷，改为通过自身 `WindowController` 或特定子窗口通道关闭/隐藏，禁止调用作用于全局主窗口的 `windowManager.close()`。
3. **僵尸进程与生命周期兜底保障**：
   - 建立窗口关闭防重入守则，保证任何实现 `WindowListener` 的组件在执行窗口关闭时均有状态保护与解绑。

## Capabilities

### New Capabilities
<!-- 无新增能力 -->

### Modified Capabilities
- `app-shell`: 增加窗口关闭事件流防重入与子窗口生命周期隔离规范，确保窗口关闭、失焦或生命周期回调不会产生无限事件递归与高 CPU 空转。

## Impact

- **Affected Code**:
  - `lib/tools/ai_video_studio/ui/studio_shell.dart`: `onWindowClose()` 防重入与自锁逻辑
  - `lib/tools/lookup_panel/ui/lookup_window.dart`: 子窗口失焦与关闭调用改造
- **APIs & Dependencies**: 严格遵循 `window_manager` 与 `desktop_multi_window` 的平台生命周期契约。
- **User Experience**: 彻底根治应用空闲及窗口关闭后 CPU 100% 狂飙、风扇狂转与系统发热问题。
