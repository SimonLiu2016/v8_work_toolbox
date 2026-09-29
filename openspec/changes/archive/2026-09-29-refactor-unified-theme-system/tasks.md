## 1. Unified Theme Contract & Extensions

- [x] 1.1 Define `AppColors` `ThemeExtension<AppColors>` in `lib/theme/app_theme.dart` with light and dark presets
- [x] 1.2 Register `AppColors.light` in `lightTheme` and `AppColors.dark` in `darkTheme`
- [x] 1.3 Ensure `BuildContext` extensions (`context.colors`, `context.bgWindow`, `context.textPrimary`, etc.) seamlessly query the extension
- [x] 1.4 Update global typography styles (`fontHeadline`, `fontTitle`, `fontBody`, `fontCaption`) to be color-neutral or derive from `ThemeData.textTheme`

## 2. Reusable Component Dynamic Theming

- [x] 2.1 Refactor `AppListItem` in `lib/components/app_components.dart` to use dynamic selection/hover backgrounds (`context.colors.bgSelected`, `context.colors.bgCardHover`) and dynamic title text color (`context.colors.textPrimary`)
- [x] 2.2 Refactor `AppCard` to default to `context.colors.bgCard` and dynamic subtle border
- [x] 2.3 Refactor `AppTextField` and `AppButton` in `lib/components/app_components.dart` to use dynamic theme colors and borders
- [x] 2.4 Refactor `ShortcutInput` in `lib/components/shortcut_input.dart` to use dynamic theme colors
  - 已核验：该文件零 token 引用，`Card` / `TextField` / `IconButton` 全部直接继承 `ThemeData`，浅色模式下本就正确，无需改动。

## 3. Top-Level Shell & System Views Normalization

- [x] 3.1 Fix hotkey option items in `lib/shell/settings_dialog.dart` to use `context.colors.bgSelected` and `context.colors.bgInput`
  - 注意：文件顶部已有一份手写的 `isDark ? AppTheme.x : AppTheme.lightX` 三元组（L98–105），应改为直接消费 `context.*`，删除这份本地映射表，避免与 ThemeExtension 双源真相。
- [x] 3.2 Update `lib/shell/tool_panel.dart` to use dynamic search input and category styling
- [x] 3.3 Update `lib/shell/app_shell.dart` to remove hardcoded `AppTheme.bgWindow` and let `Scaffold` inherit `ThemeData.scaffoldBackgroundColor`
  - 已部分完成：`VerticalDivider` 与主工作区背景已改 `context.*`。**剩余 L156 根 `Scaffold(backgroundColor: AppTheme.bgWindow)`** 未处理，这是浅色模式下最大的一块深色矩形，必须一并移除。
- [x] 3.4 Update `lib/shell/ai_config_page.dart` root container and tabs to use dynamic theme background and borders
  - 涉及 L325 `_healthColor()` 与 L843 等已在 build 外的引用点，需把 `BuildContext` 传进去，不能就地读 `context`。
- [x] 3.5 Update `lib/shell/ai_log_dialog.dart` to use dynamic dialog surface color and borders
  - 含 8 处 `const Icon/Text/Divider` 包裹的静态 token，需逐处摘除 `const`。
- [x] 3.6 Update `lib/tools/network_proxy/ui/network_proxy_page.dart` root container to use dynamic theme background
- [x] 3.7 Wire `_SingleNoteWindowApp` in `lib/main.dart` (L490) to `theme: AppTheme.lightTheme` / `darkTheme: AppTheme.darkTheme` / `themeMode: SettingsStore.instance.themeModeNotifier`
  - 现状：该文件是 5 个 `MaterialApp` 中唯一未接主题的实例，用 `ThemeData.light().copyWith(...)`，导致暗色模式静默失效且 `context.colors` 无扩展可查。
- [x] 3.8 Replace the silent fallback in `ThemeContextExtension.colors` (`lib/theme/app_theme.dart` L449) with a debug 期硬失败
  - 现状 `Theme.of(this).extension<AppColors>() ?? (isDarkMode ? AppColors.dark : AppColors.light)` 会把漏接主题的窗口伪装成可用。改为 `assert` + 兜底深色，让 3.7 这类遗漏在开发期立即暴露，而不是留给用户。

## 4. Tool Scaffolds & Verification

- [x] 4.1 Remove hardcoded `backgroundColor: AppTheme.bgWindow` from tool pages (`ops_tool_main_page.dart`, `password_page.dart`, `private_media_player_page.dart`)
  - `vocab_book_page.dart` 已从本任务移除，理由见 §5。
- [x] 4.2 Verify project compilation with `flutter analyze`
- [x] 4.3 Build release bundle and verify light/dark switching behavior

## 5. Scope Boundary — deferred to follow-up change

以下内容经评估后**刻意排除在本 change 之外**，由后续 change「清理工具页静态主题 token」承接：

- 全代码库剩余 **793 处** `AppTheme.<dark token>` 静态引用，分布于 45 个文件（`vocab_book` 48 / `ops_tool` 85 / `private_player` 75 / `password` 80 / `slimmer` 56 / `unattended` 58 / `notebook` 36 / 9 个独立工具总入口约 90 处等）。
- 其中 **164 处**位于 `const` 表达式内，需逐处摘除 `const`，无法批量替换。
- **`vocab_book_page.dart` 归属冲突**：`lib/tools/vocab_book/` 由 `add-context-menu-lookup-vocab-note`（44/48 未完成）新建且当前未被 git 跟踪；该 change 的任务清单经检索确认不含任何样式类任务，故 vocab_book 的 48 处引用目前无主。为避免两个 change 同时修改同一文件，其清理移至后续 change。
- **长期设计议题**：`AppColors` 的 14 个 token 与 `ColorScheme` 已有角色高度重叠（`bgCard`↔`surface`、`textPrimary`↔`onSurface`、`borderSubtle`↔`outlineVariant`…）。是否向 Material 3 `ColorScheme` 语义角色迁移，需在后续 change 中独立评估，本 change 不动。

本 change 的判定标准是：**用户在浅色模式下看得见的每一层表面（窗口根、活动栏、侧栏、内容区、设置、对话框、主配置页、工具页根部）均可随主题切换**，不承诺工具页内部细节的完整性。
