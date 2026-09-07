## Context

目前应用图标缺乏高辨识度与设计感，工程中的 `AppIcon.appiconset` 仅为初版文字图标。同时，macOS 原生状态栏托盘在 `AppDelegate.swift` 中采用了带文字 `" V8"` 的 `NSStatusItem.variableLength` 动态宽度配置，在刘海屏或状态栏较拥挤的设备上极易被系统折叠。

## Goals / Non-Goals

**Goals:**
- 将官方选定的 **款式 3：六边形钛合金工具匣 (Hex Titanium Core)** 制作成 1024x1024 的原图，并使用高质量缩放生成 16x16、32x32、64x64、128x128、256x256、512x512、1024x1024 全尺寸 `AppIcon.appiconset`。
- 制作符合 macOS Human Interface Guidelines 标准的纯黑单色 Template 托盘图标 `TrayIcon.imageset`（18x18@1x, 36x36@2x）。
- 重构 `AppDelegate.swift` 中的 `setupStatusItem`：
  - 改用 `statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)`；
  - 移除冗余文本标题，只展示高对比度的 Template 图标；
  - 增强点击事件与菜单呼出体验，保证 100% 稳固常驻。
- 在 Flutter 桌面端活动栏（ActivityBar）与设置关于界面呈现统一品牌形象。

**Non-Goals:**
- 不引入重型第三方托盘插件（自写轻量 Swift 原生桥接维护性最好、零第三方冲突）。

## Decisions

### D1 应用图标全尺寸生成流水线
- 使用 Python PIL 高质量 Lanczos 采样，将高清源图渲染为 1024、512、256、128、64、32、16 全套规范 PNG。
- 覆盖 `macos/Runner/Assets.xcassets/AppIcon.appiconset/` 并同步更新 `Contents.json`。

### D2 原生状态栏 TrayIcon 标准化
- 在 `macos/Runner/Assets.xcassets/TrayIcon.imageset/` 创建 18x18 与 36x36 专用的 Template 图标。
- `AppDelegate.swift` 使用 `NSImage(named: "TrayIcon")`，并显式声明 `image.isTemplate = true`，当系统切换 Dark/Light Mode 时由 Cocoa 框架自动计算最佳反转对比色。
- 使用 `NSStatusItem.squareLength` 固定方形尺寸（22pt），彻底规避 macOS 系统对于文本类状态栏条目的隐藏惩罚。

### D3 快捷唤起与主窗口响应
- 保持全局快捷键 `⌥Space` 与菜单栏左键点击一致（唤起/隐藏主窗口）。
- 右键点击依然无缝弹出包含“打开主窗口”与“退出应用”的上下文菜单。

## Risks / Trade-offs

- **[macOS 缓存应用图标不及时刷新]** → 缓解：重新 build 时触发 bundle 重建，必要时执行 `touch /Applications/` 或针对 runner 执行强制重载。
