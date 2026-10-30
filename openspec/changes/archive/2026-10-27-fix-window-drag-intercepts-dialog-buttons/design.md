## Context

macOS `isMovableByWindowBackground = true` 是一个 NSWindow 级别的属性，使得点击窗口内容区（即 FlutterView）背景时触发窗口拖拽。Flutter 引擎的 FlutterView 默认实现 `mouseDownCanMoveWindow` 返回 `true`，这与 `isMovableByWindowBackground = true` 共同作用的结果是：**NSWindow 在收到落在 FlutterView 上的任意 mouseDown 时，无论是否命中 Flutter 的可交互 widget，都会优先开始窗口拖拽，事件不再传入 Flutter 事件系统**。

上次修复尝试调整了 Dialog 的 `insetPadding.top`（52px），方向完全错误——问题与弹窗相对屏幕的位置无关，任何位置的弹窗内按钮都会失效。

`window_manager` 包提供了 `DragToMoveArea` widget 和 `windowManager.startDragging()` API，可在 Flutter 层精确圈定可拖拽区域，完全替代全局背景拖拽。

## Goals / Non-Goals

**Goals:**
- 移除所有 `isMovableByWindowBackground = true` 设置
- 用 `DragToMoveArea` 包住 ActivityBar 顶部 38px 区域，保留拖窗功能
- 使所有 showDialog / showModalBottomSheet 弹窗内的控件点击完全恢复

**Non-Goals:**
- 不修改弹窗的尺寸、位置、padding（那是上次错误修复引入的，保留不动，没有害处）
- 不重构 AppShell 的三栏布局

## Decisions

### 1. 移除 isMovableByWindowBackground

在以下两个文件移除该属性：
- `macos/Runner/MainFlutterWindow.swift`：删除 `self.isMovableByWindowBackground = true`
- `macos/Runner/AppDelegate.swift`：删除 `FlutterMultiWindowPlugin.setOnWindowCreatedCallback` 内的 `window.isMovableByWindowBackground = true`

子窗口（查词浮窗、实时字幕）本来也不需要全局背景拖拽，它们各自有自己的拖拽逻辑（`live_caption_window.dart` 用 onPanStart → windowManager.startDragging()）。

### 2. DragToMoveArea 包住 ActivityBar 顶部 38px

ActivityBar 顶部已有 `const SizedBox(height: 38)` 作为 macOS 交通灯按钮预留高度，这片空白区天然是拖窗把手。将其替换为：

```dart
import 'package:window_manager/window_manager.dart';
// ...
DragToMoveArea(
  child: const SizedBox(height: 38, width: double.infinity),
),
```

`DragToMoveArea` 内部使用 `GestureDetector(behavior: HitTestBehavior.translucent)`，不会阻断子 widget 的点击事件，且双击自动触发最大化/还原。

### 3. 范围确认

只改主窗口的 `isMovableByWindowBackground`。子窗口（lookup_window、it_listening_mini_player）走 `desktop_multi_window` 机制，同在 `AppDelegate.swift` 的回调里也会被清除，统一处理。

## Risks / Trade-offs

- **双击最大化**：`DragToMoveArea` 自带双击最大化行为，与之前整个窗口背景双击无最大化行为略有不同——但这是标准桌面约定，是改善，不是退步。
- **旧的修复引入的多余 padding**：上次 `insetPadding top: 52` 依然存在，没有 bug，只是略微浪费了一点对话框可视高度，可在此次一并回滚至 `vertical: 24`，也可留着不动。
