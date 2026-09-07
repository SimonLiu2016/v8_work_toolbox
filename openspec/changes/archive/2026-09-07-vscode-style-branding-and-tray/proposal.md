## Why

当前 V8 Work Toolbox 的机械风格 Logo 与六边形托盘图标视觉风格偏向传统五金机械，缺少现代顶尖开发者生产力工具（如 Visual Studio Code）所具备的几何极简、立体折面与灵动流线质感。为了提升品牌专业度与视觉辨识度，决定重构主界面 Logo、macOS Dock 图标与顶部菜单栏托盘图标，采用用户选定的“款式 2：流线莫比乌斯极客款 (Flowing Ribbon V8)”设计语言。

## What Changes

- **应用图标升级 (macOS Dock AppIcon)**：基于款式 2（一笔画连续流动折带）提取透明标准 Squircle（macOS 22.4% 连续曲率大圆角）高清图标，生成全套标准分辨率（16x16 至 1024x1024），替换 `macos/Runner/Assets.xcassets/AppIcon.appiconset`。
- **托盘图标升级 (macOS Menu Bar Tray)**：提取流线折带核心负空间外轮廓，生成 18x18@1x 与 36x36@2x 纯黑 Template 矢量剪影，更新 `TrayIcon.imageset`，实现深浅色模式自动反色与高锐度显示。
- **主界面 ActivityBar 品牌集成**：更新 `assets/images/app_logo.png` 与相关 UI 呈现组件，在 ActivityBar 顶部与设置关于弹窗中优雅融入流线折带 V8 品牌标识。
- **原生打包与部署同步**：重新打包 Release 应用并同步至 `/Applications/V8WorkToolbox.app`，刷新系统缓存。

## Capabilities

### Modified Capabilities
- `theme-and-brand`: 更新应用图标与品牌视觉系统，采用 VS Code 风格莫比乌斯流线折带 (V8 Origami Ribbon) 资产体系。
- `menu-bar-launcher`: 更新系统托盘状态项图标，使用匹配新款式 2 的 18x18 Template 矢量资产。

## Impact

- `macos/Runner/Assets.xcassets/AppIcon.appiconset/` 中的全套 PNG 图标文件
- `macos/Runner/Assets.xcassets/TrayIcon.imageset/` 中的托盘模板图标
- `assets/images/app_logo.png` 及 Flutter 端引用组件（`ActivityBar`、`SettingsDialog`）
- macOS 原生 Release 包构建与 `/Applications/V8WorkToolbox.app` 安装同步
