## Why

当前 V8WorkToolbox 缺乏高辨识度与现代感的应用视觉设计（原有 Logo 仅为简单的纯色文字），且 macOS 顶部菜单栏托盘图标因使用文本拼接与变长按钮尺寸而在刘海屏和多图标环境下被系统折叠隐藏无法正常显示。本次变更旨在彻底解决原生托盘常驻可见性问题，并对全套应用图标（AppIcon）、原生系统托盘图标（TrayIcon）与界面内品牌标识进行现代化升级。

## What Changes

- **全套原生 AppIcon 资产升级（款式 3：六边形钛合金工具匣 / Hex Titanium Core）**：生成覆盖 macOS 规范（16x16 到 1024x1024 全尺寸）的高清资产，替换 `Assets.xcassets/AppIcon.appiconset`。
- **macOS 顶部系统托盘图标标准化（TrayIcon）**：
  - 新增 18x18@1x 与 36x36@2x 规范的纯黑白 Template 托盘矢量图标资产至 `Assets.xcassets/TrayIcon.imageset`。
  - 重构 `AppDelegate.swift` 中的 `setupStatusItem()`，改用 `NSStatusItem.squareLength` 紧凑方块尺寸，移除易被系统折叠的文字标题，设置 `isTemplate = true` 以完美自适应 macOS 浅色与深色菜单栏。
- **Flutter 界面品牌标识呈现**：在主界面侧边活动栏（ActivityBar）或关于弹窗中呈现一致的品牌视觉徽标。

## Capabilities

### New Capabilities
<!-- 无新增独立业务能力 -->

### Modified Capabilities
- `workspace-navigation`: 更新 macOS 菜单栏托盘（Menu bar tray presence）需求，明确采用 `NSStatusItem.squareLength`、自适应 Template 图标与消除文字截断的交互标准。

## Impact

- **原生工程资产**：`macos/Runner/Assets.xcassets/AppIcon.appiconset` 与 `macos/Runner/Assets.xcassets/TrayIcon.imageset`。
- **原生代码**：`macos/Runner/AppDelegate.swift` 中的托盘状态项初始化与渲染逻辑。
- **Flutter 页面**：主界面及偏好设置关于界面的品牌形象呈现。
