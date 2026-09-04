# UI 全面重构：Raycast 风深色工具箱

## Why

当前应用是 Material 2 默认样式的移动端卡片墙布局，直接搬上 macOS 桌面，视觉上粗糙违和。软件定位为"个人小工具集合包"并将持续增加工具，但现有架构每加一个工具都要手工修改 `main.dart` 的 GridView，配置也散落在 `~/` 下各工具自管的 JSON 文件中。需要一次彻底的 UI 层重构，同时建立支撑长期扩展的外壳架构。

## What Changes

- **重做应用外壳**：废弃 2 列卡片墙首页，改为"侧边栏 + 内容区"的桌面布局，深色 Raycast 风格设计（深色底、紧凑排版、毛玻璃质感、键盘优先交互）。
- **设计系统**：建立统一的设计 token（色板、字体、间距、圆角），所有工具页在新设计系统下重写 Widget 树。
- **工具注册表**：引入插件化的工具注册机制，新工具 = 一个新文件 + 一行注册，外壳零改动；侧边栏按分类分组、支持搜索过滤和最近使用。
- **菜单栏常驻 + 全局唤起**：应用常驻 macOS 菜单栏（Tray 图标），支持全局快捷键快速唤起/隐藏主窗口，关闭窗口不退出应用。
- **统一配置存储**：所有工具的配置迁移到 `~/Library/Application Support/V8WorkToolbox/` 统一管理，废弃散落在 `~/` 的 `.*.json` 文件（含旧配置一次性迁移）。
- **8 个现有工具功能全部保留**：业务逻辑（KMA 加密、XML 解析、正则重命名、图片处理、Accessibility 桥接等）不动，仅重写各工具页的 UI 层。

## Capabilities

### New Capabilities

- `app-shell`: 应用外壳——侧边栏导航、工具注册表、分类分组、搜索过滤、深色主题渲染、窗口管理。
- `menu-bar-launcher`: 菜单栏常驻图标、全局快捷键唤起/隐藏主窗口、关闭窗口转为后台驻留的行为。
- `settings-storage`: 统一的应用配置存储——存储位置、读写规范、旧配置迁移。

### Modified Capabilities

（无 —— 项目尚无既有 specs；8 个工具的既有功能行为不变，仅 UI 表现层重写，不产生 spec 级行为变更。）

## Impact

- **代码**：`lib/main.dart` 整体重写；新增外壳层（主题、注册表、侧边栏、设置存储）；8 个工具页（`bc_config_tool.dart`、`bc_config_shell.dart`、`batch_rename_tool.dart`、`folder_compare_tool.dart`、`kma_package_tool.dart`、`image_resize_tool.dart`、`app_shortcut_tool.dart`、`clean_builds_tool.dart`）的 UI 层逐个重写，业务逻辑保留。
- **macOS 原生层**：`macos/Runner` 需增加菜单栏（NSStatusItem）与全局快捷键支持（Swift 侧 + MethodChannel）。
- **依赖**：可能新增窗口管理 / 全局快捷键相关 Flutter 插件（如 `window_manager`、`hotkey_manager` 或自实现原生桥）。
- **用户数据**：旧配置文件（如 `~/.v8_cleaner_config.json`）在首次启动时迁移，迁移后旧文件保留不删（安全回退）。
- **不影响**：所有工具的核心业务逻辑、KMA 加密格式、导出文件格式、`AppShortcutsHandler.swift` 的 Accessibility 提取逻辑。
