# Tasks: Raycast 风深色工具箱 UI 重构

## 1. 基础设施：设计系统与外壳

- [x] 1.1 新增 `path_provider` 依赖；创建 `lib/theme/app_theme.dart`，定义设计 token（深色色板、字体四档、4 基数间距、圆角）与全局 `ThemeData`
- [x] 1.2 创建薄封装组件库（`AppTextField`、`AppButton`、`AppCard`、`AppListItem`、提示条等），全部只引用 token
- [x] 1.3 创建工具注册表：`ToolDefinition` 抽象、`ToolCategory` 枚举、`lib/tools/registry.dart` 注册点
- [x] 1.4 创建应用外壳：侧边栏（搜索框 + 最近使用 + 分类分组列表）+ `IndexedStack` 内容区，含键盘导航（↑↓/Enter）
- [x] 1.5 重写 `main.dart`：应用新 ThemeData 与外壳，将 8 个现有工具页以 `ToolDefinition` 薄适配器挂入注册表（旧 UI 暂保留，先跑通）
- [x] 1.6 设置窗口最小尺寸（约 900×600）与默认尺寸（约 1100×700）；删除旧卡片墙与 `BcConfigApp` 死代码

## 2. 菜单栏与全局快捷键（macOS 原生桥）

- [x] 2.1 在 `macos/Runner/AppDelegate.swift` 实现 `NSStatusItem` 菜单栏图标与菜单（打开主窗口 / 退出）
- [x] 2.2 实现 Carbon `RegisterEventHotKey` 全局快捷键注册（默认 `⌥Space`，注册失败时降级并提示），通过 MethodChannel 暴露给 Dart
- [x] 2.3 实现唤起/隐藏逻辑：快捷键与菜单触发时 `NSApp.activate` + 显示/聚焦窗口，前台再按则隐藏
- [x] 2.4 关闭窗口不退出：`applicationShouldTerminateAfterLastWindowClosed = false`，关闭时隐藏窗口，菜单栏"退出"才真正退出
- [x] 2.5 设置页（或外壳设置区）：全局快捷键可配置、冲突提示，持久化到 `app.json`

## 3. 统一配置存储与迁移

- [x] 3.1 实现 `SettingsStore`：基于 `getApplicationSupportDirectory()`，按 `config/<tool-id>.json` + `app.json` 布局读写，原子写 + 损坏回退默认配置
- [x] 3.2 全量 grep 各工具旧持久化点（`File(`、`HOME`、`.json` 等），编制旧配置迁移表
- [x] 3.3 实现启动时一次性迁移：按迁移表复制旧文件内容到新存储，目标已存在则跳过，旧文件保留，迁移记录写入 `app.json`
- [x] 3.4 最近使用记录通过 `SettingsStore` 持久化，接入侧边栏"最近使用"区域

## 4. 工具页 UI 换皮（功能等价，小→大）

- [x] 4.1 清理构建产物页换皮 + 配置读写切换到 `SettingsStore`，人工对照旧版功能
- [x] 4.2 应用快捷键获取页换皮，人工对照旧版功能
- [x] 4.3 图片尺寸修改页换皮，人工对照旧版功能
- [x] 4.4 批量重命名页换皮，人工对照旧版功能
- [x] 4.5 BC 配置工具页换皮，人工对照旧版功能
- [x] 4.6 BC 脚本管理页换皮，人工对照旧版功能
- [x] 4.7 文件夹对比页换皮，人工对照旧版功能
- [x] 4.8 KMA 包生成页换皮（1871 行，最大），人工对照旧版功能

## 5. 收尾

- [x] 5.1 删除所有旧配置读取路径与 `~/` 散落写文件的代码；验证主目录不再新增配置文件
- [x] 5.2 迁移验证：构造旧配置文件场景，确认首次启动迁移正确、二次启动不重复迁移、损坏配置不崩溃
- [x] 5.3 `flutter analyze` 零告警；`flutter build macos` 通过
- [x] 5.4 全量人工验收：8 个工具功能行为与旧版一致；深色主题下逐页检查对比度与视觉一致性
- [x] 5.5 更新 README（新界面截图、快捷键说明、配置目录变更说明）
