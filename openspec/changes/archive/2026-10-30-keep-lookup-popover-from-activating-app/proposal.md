## Why

从浏览器伴侣点「问 AI 深度解析」或「加入词本」后，查词浮窗正常出现了，但**主窗口也一并被带到前台**——把用户正在看的网页盖掉。用户明确说"如果不弹出主窗体更好"。

根因一行：`LookupWindowLauncher.open()` 调了 `await controller.show()`，而 `desktop_multi_window` 的 `window_show` 处理器写死了一套三连：

```swift
case "window_show":
    window.makeKeyAndOrderFront(nil)
    window.setIsVisible(true)
    NSApp.activate(ignoringOtherApps: true)   // ← 把整个 App（含主窗口）带到前台
```

**这不只是深链的问题，也不只是这次改动引入的。** 五个子窗口都走 `WindowController.create` + `show()`，行为完全一样。只是查词浮窗的定位是"不打断阅读的气泡"，激活 App 与它的定位直接矛盾；而其他四个工具窗口激活 App 是合理的（用户点了"打开笔记本"，App 该亮）。

值得注意的是，同一个仓库里的 `configureLookupWindow()` 已经在防这件事——它做 `makeKeyAndOrderFront` 但不 `activate`。说明当初有人意识到过，只是 `controller.show()` 跑在它前面，activate 已经发生。

## What Changes

- **查词浮窗创建后不再调用 `controller.show()`**：`desktop_multi_window` 的 `CreateWindow` 在 `hiddenAtLaunch: false` 时已经 `orderFront(nil)` + `setIsVisible(true)`，这行 `show()` 在这个场景下是多余的，代价却是激活整个 App。
- **只改查词浮窗**：其余四个子窗口保持现状——它们激活 App 是用户预期内的行为。

## Capabilities

### New Capabilities

- 无。

### Modified Capabilities

- `browser-lookup-deep-link`: 从浏览器深链打开的查词浮窗不得把宿主 App（连同主窗口）带到前台——浮窗该是贴靠光标的轻气泡，不是一次应用切换。

## Impact

- **Flutter 层**：`lib/tools/lookup_panel/ui/lookup_window.dart`（删掉 `await controller.show()`，一行）。
- **不受影响**：`⌘D` 热键、macOS Services、右键查词三条路径仍走同一个 `open()`——它们本来就在 App 内，激活与否用户无感；改动后它们同样不再激活 App，这是行为收敛而非回退。
- **依赖**：无。**数据**：无。**原生层**：无。
- **非目标**：不改 `desktop_multi_window` 包(hosted 依赖，改不动)；不给其他四个子窗口加"是否激活"的开关(它们的当前行为是对的)；不做"主窗口已隐藏时把它带回来"这类额外逻辑。
