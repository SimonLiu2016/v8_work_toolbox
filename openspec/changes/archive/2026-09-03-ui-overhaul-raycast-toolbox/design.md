# Design: Raycast 风深色工具箱 UI 重构

## Context

现有 Flutter 应用（~13.8k 行 Dart，8 个工具页），Material 2 默认样式，卡片墙首页在 `main.dart` 中硬编码。业务逻辑（加密、解析、文件处理）与 UI 混在 StatefulWidget 中但大体可读。已有 Swift 原生桥（`AppShortcutsHandler.swift`，Accessibility API）。配置散落在 `~/` 下（已知 `~/.v8_cleaner_config.json`，需在实现时普查其余工具的持久化点）。动机见 proposal.md。

## Goals / Non-Goals

**Goals:**
- 建立设计 token 层与外壳架构，使 8 个工具页 UI 在统一规范下重写。
- 插件化工具注册：新增工具只新增文件，不改外壳。
- 菜单栏常驻 + 全局快捷键唤起。
- 统一配置存储并完成旧配置迁移。
- 每个工具页重写后功能行为与旧版一致（可人工对照验收）。

**Non-Goals:**
- 不重写任何工具的业务逻辑（KMA 加密、YAML 对比、图片处理等保持原实现与格式兼容）。
- 不引入状态管理框架的迁移（如 Bloc/Riverpod 全量改造）——仅在必需处做轻量抽离。
- 不做 Windows/Linux/Web 端的适配（本次仅 macOS）。
- 不做工具的 UI/交互流程再设计（如把三步向导改成一步）——保持功能等价，只换视觉与外壳。

## Decisions

### D1: 保留 Flutter，自绘 Raycast 风主题，不用 `macos_ui`

用户已选定 Raycast 深色风。`macos_ui` 提供的是原生 AppKit 观感（Finder 风），与 Raycast 风目标相反，故不采用。用 Material 3 作为控件基础，通过自定义 `ThemeData` + 设计 token 压出深色紧凑风格。

**备选**：SwiftUI 原生重写（弃：13.8k 行已验证逻辑重写成本高、风险大）；Tauri（弃：同上且原生桥要重搭）。

### D2: 设计 token 集中在单一 theme 文件

新建 `lib/theme/app_theme.dart`（或同等位置），定义：
- 色板：背景分层（window / sidebar / card / hover）、主文字/次文字/弱文字三级灰、单一强调色（蓝紫系，Raycast 感）、语义色（成功/警告/错误）。
- 字体：SF Pro 系（macOS 默认），标题/正文/说明/等宽四档字号行高。
- 间距：4 为基数的阶梯（4/8/12/16/24），圆角 6/10。
- 所有工具页只允许引用 token，禁止散落硬编码 `Colors.blue`、`EdgeInsets.all(16)` 之类。

### D3: 外壳布局：侧边栏 + 内容区，自绘不依赖第三方桌面框架

```
┌──────────┬───────────────────────────────┐
│ 搜索框    │                               │
│ ──────── │                               │
│ 最近使用  │        当前工具页              │
│ ▸ 文件    │   （Navigator 换成索引栈，    │
│ ▸ 包/构建 │    保持工具页状态不丢失）      │
│ ▸ 系统    │                               │
└──────────┴───────────────────────────────┘
```

- 内容区用 `IndexedStack` 而非 `Navigator.push`：切换工具不销毁状态（对比旧版 push 是行为增强，且更符合桌面 App 直觉）。
- 搜索框置顶侧边栏，`TextField` + 键盘导航（↑↓ 移动、Enter 打开）。
- 窗口最小尺寸约束（约 900×600），默认 1100×700。

### D4: 工具注册表：编译期显式注册，不做反射/插件发现

```dart
abstract class ToolDefinition {
  String get id;            // 稳定标识，用于最近使用持久化
  String get title;
  String get subtitle;
  IconData get icon;
  ToolCategory get category;
  Widget buildPage(BuildContext context);
}

// lib/tools/registry.dart —— 唯一的注册点
final registry = <ToolDefinition>[
  BcConfigTool(), BatchRenameTool(), ...
];
```

**备选**：运行时插件发现/动态加载（弃：个人工具箱无此需求，编译期注册简单可靠、类型安全）。新增工具的成本 = 新建一个文件 + registry 里加一行。

### D5: 菜单栏与全局快捷键：自写 Swift 原生桥，复用现有 MethodChannel 模式

项目已有 Swift↔Flutter 的 MethodChannel 先例（AppShortcutsHandler）。菜单栏（`NSStatusItem`）和全局快捷键（`NSEvent.addGlobalMonitorForEvents` 或 Carbon `RegisterEventHotKey`）在 `AppDelegate.swift` 中实现，通过新 channel 与 Dart 通信。

- **快捷键方案选 Carbon RegisterEventHotKey**：`NSEvent` 全局监听需要辅助功能权限且对某些组合键不灵；Carbon hotkey 是真正的全局注册，权限要求低。默认快捷键建议 `⌥Space` 或 `⌃⌥K`（避开系统 Spotlight 的 `⌘Space`），冲突时按 spec 提示并可配置。
- 关闭窗口不退出：`applicationShouldTerminateAfterLastWindowClosed` 返回 `false`，配合 window delegate 隐藏而非销毁。

**备选**：`window_manager` + `hotkey_manager` 插件（备选保留：若自写桥遇到窗口焦点/激活策略问题可引入，插件底层同样是这两个原生 API；但菜单栏 Tray 仍需自写或用 `tray_manager`，评估后选自写——三个需求集中在一个 Swift 文件里反而比三个插件好维护）。

### D6: 统一配置存储：`SettingsStore` 单例 + 每工具一个 JSON 文件

- 路径：`~/Library/Application Support/V8WorkToolbox/`，Flutter 侧直接用 `path_provider` 的 `getApplicationSupportDirectory()`（新增依赖 `path_provider`）。
- 布局：`config/<tool-id>.json`（各工具配置）+ `app.json`（全局：快捷键、最近使用、窗口尺寸）。
- API：`SettingsStore.read(toolId)` / `write(toolId, json)`，内部做原子写（先写临时文件再 rename）与损坏回退（解析失败 → 返回默认值 + 记录错误，UI 层显示提示条）。
- 各工具现有的"load/save 配置"代码改为走 `SettingsStore`，UI 重写时顺带完成。

### D7: 旧配置迁移：启动时一次性复制

- 迁移表（实现时普查补全）：`~/.v8_cleaner_config.json` → `config/clean-builds.json`，其余工具在重写各页时逐个确认旧持久化点并加入迁移表。
- 判定"已迁移"：目标文件存在即跳过（不比对内容），旧文件永不删除。
- 在 `app.json` 记录 `migratedFrom: [...]` 便于排查。

### D8: 工具页重写方式：逐页"UI 换皮"，逻辑原地保留

每个工具页按同一模式改造：保留现有 State 字段与方法（业务逻辑），只替换 `build()` 的 Widget 树为新设计系统组件（`AppTextField`、`AppButton`、`AppCard` 等一组薄封装）。KMA 工具（1871 行）最大，优先做外壳 + 小工具页验证设计系统后再啃。

## Risks / Trade-offs

- [IndexedStack 常驻所有工具页可能占内存] → 工具页均为轻量表单/列表，8 页体量可接受；若未来工具页变重，改为懒加载缓存策略（接口不变）。
- [Carbon hotkey API 为废弃状态（deprecated 但仍可用）] → macOS 上仍是全局快捷键的事实标准实现（Raycast 同类方案）；封装在 Swift 桥内，未来替换不影响 Dart 侧。
- [全局快捷键与其他 App 冲突] → 按 spec 提供设置页修改快捷键；注册失败降级为仅菜单栏唤起。
- [菜单栏图标/激活策略细节（Dock 图标显隐、后台激活）易踩坑] → 默认保留 Dock 图标（用户可预期），不做 `LSUIElement` 纯后台化；唤醒时 `NSApp.activate`。
- [迁移表可能遗漏某工具的旧配置点] → 实现任务中包含"全量 grep 持久化调用"步骤，逐个核对。
- [深色主题下图标/图片对比度] → 设计 token 中定义禁用/弱态颜色，逐页验收时检查。

## Migration Plan

1. 新增 theme / registry / shell / SettingsStore 基础设施，8 个旧页面暂时挂进新外壳（先丑着能跑）。
2. 菜单栏 + 全局快捷键 Swift 桥。
3. 配置迁移 + 各工具配置读写切换到 SettingsStore。
4. 按"小→大"顺序逐工具页换皮：clean_builds → app_shortcut → image_resize → batch_rename → bc_config → bc_config_shell → folder_compare → kma_package。
5. 删除旧 `main.dart` 卡片墙与旧配置读取路径。
6. 全量人工对照验收：每个工具功能行为与旧版一致。

**回滚**：本次为纯客户端重构，回滚 = git revert；旧配置文件未删除，回滚后旧版本可正常读取。

## Open Questions

- 默认全局快捷键的最终选择（`⌥Space` vs `⌃⌥K`）——实现时验证冲突情况后定，设置页可改，不影响 spec 与任务拆解。
- 是否在菜单栏菜单中加入"最近使用的工具"快捷入口——增量增强，可在主体完成后追加，不阻塞。
