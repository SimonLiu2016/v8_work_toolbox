## Why

macOS `isMovableByWindowBackground = true` 使得 FlutterView 的任何 mouseDown 事件都可能触发 NSWindow 的原生拖窗行为，导致 showDialog / showModalBottomSheet 弹出的模态窗口（如分镜媒体预览弹窗、道具资产编辑抽屉）中的所有按钮点击被系统级吞没，Flutter 的事件路由永远收不到 onTap。此前修复尝试调整了弹窗位置（insetPadding top），方向完全错误——问题与弹窗位置无关。

## What Changes

1. **原生侧（macOS Swift）**：移除 `MainFlutterWindow.swift` 和 `AppDelegate.swift` 中所有 `isMovableByWindowBackground = true` 的设置，改为仅在需要时由 Flutter 侧精确控制。
2. **Flutter 侧（Dart）**：在 `ActivityBar` 顶部的 38px 系统预留空白区套上 `DragToMoveArea` widget，使该区域成为唯一的拖窗把手，恢复窗口可拖拽性。

## Capabilities

### New Capabilities
<!-- 无新能力 -->

### Modified Capabilities
- `app-shell`: 明确窗口拖拽区域的交互规范——拖窗操作 SHALL 仅由 ActivityBar 顶部的专用可拖拽区响应，全局 `isMovableByWindowBackground` MUST NOT 启用，以防止模态弹窗内的控件点击被 NSWindow 原生截获。

## Impact

- `macos/Runner/MainFlutterWindow.swift`：移除 `isMovableByWindowBackground = true`
- `macos/Runner/AppDelegate.swift`：移除所有子窗口的 `isMovableByWindowBackground = true`
- `lib/shell/activity_bar.dart`：顶部 38px SizedBox 替换为 `DragToMoveArea`
- 不影响数据模型、AI 调用、持久化格式
