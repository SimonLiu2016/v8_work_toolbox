## Why

`refactor-unified-theme-system` 已把 `AppColors` `ThemeExtension`、`context.colors` 契约、Shell/设置/对话框/工具页根部全部接入动态主题，并在该 change 的 §5 明确把"工具页深水区"划为本 change 的范围。当前 `lib/` 下仍有 **671 处** `AppTheme.<静态深色 token>` 引用，分布在 38 个文件；其中 **139 处**被困在 `const` 表达式中，连批量替换都无法覆盖。

这些残留使浅色模式下工具页内部大面积失效：深灰卡片 (#2D2D30) 叠在白底窗口上、浅灰文字 (#D4D4D4) 落在白卡片上、深色边框 (#3C3C3C) 在白底上几乎不可见。用户切到浅色模式后，Shell 是亮的、一进工具页就"破功"。

## What Changes

- **将 38 个文件的 671 处静态 token 引用全部改走 `context.<token>`**，按工具域分批推进，每批独立可验证。
- **逐处摘除 139 处 `const` 包裹**（`const Icon(... color: AppTheme.textTertiary)` / `const TextStyle(...)` / `const Divider(...)` 等）。这是本次的主要工作量，无法用 sed 完成。
- **清理硬编码的 `Scaffold(backgroundColor: AppTheme.bg*)`**：工具页根 Scaffold 改由 `ThemeData.scaffoldBackgroundColor` 继承，不再显式指定。
- **`lib/tools/vocab_book/ui/vocab_book_page.dart` 纳入本次范围**：该目录由 `add-context-menu-lookup-vocab-note` 新建且尚未被 git 跟踪，但该 change 的任务清单经检索确认不含任何样式类任务，故其 48 处引用（24 处 const）目前无主。本次接管，避免长期悬空。
- **新增 lint 防线**：引入一条 `avoid_static_theme_tokens` 自定义 lint（或等效的 analyze 扫描脚本），禁止在 widget 代码中新增 `AppTheme.<颜色 token>` 引用，只允许 `lib/theme/app_theme.dart` 内部使用。防止第 671 处之后再生出第 672 处。
- **不引入新视觉设计**：全部沿用 `AppColors.light` / `AppColors.dark` 已定义好的 token 值，不调色、不加新色、不改变深色模式下的现有观感。

**非目标（明确不做）：**
- 不评估 `AppColors` 向 Material 3 `ColorScheme` 语义角色的迁移（14 个 token 与 `ColorScheme` 高度重叠），该议题独立立项。
- 不修改 `lib/theme/app_theme.dart` 中的 token 定义与 ThemeData 配置本身。
- 不给工具页补充新的浅色专属设计；浅色下的视觉正确性 = 现有 token 派生的结果。

## Capabilities

### New Capabilities

无。本次不改动 spec 层行为契约——工具页内部的颜色来源属于实现细节，不构成用户可观察的需求变更。用户的浅色模式需求已由 `theme-and-brand` 中"Dynamic theme inheritance for reusable components"与 `add-global-theme-and-fix-companion-lookup` 覆盖。

### Modified Capabilities

- `theme-and-brand`: 收紧 "Dynamic theme inheritance for reusable components" 需求的覆盖范围声明，把"所有工具页内部视图"纳入动态继承的约束，并为"源码中不再存在 widget 层静态 token 引用"补充一个可验证场景。

## Impact

**代码（38 个文件，671 处引用）：**

| 域 | 文件数 | 引用数 | const 数 |
|---|---|---|---|
| `lib/tools/unattended/` | 1 | 58 | 12 |
| `lib/tools/slimmer/` | 1 | 56 | 4 |
| `lib/tools/vocab_book/` | 1 | 48 | 24 |
| `lib/tools/ops_tool/` | 6 | 102 | 8 |
| `lib/tools/private_player/` | 4 | 76 | 34 |
| `lib/tools/password/` | 7 | 108 | 18 |
| `lib/tools/notebook/` | 3 | 37 | 5 |
| `lib/tools/ai_assistant/` | 2 | 36 | 8 |
| `lib/tools/lookup_panel/` | 1 | 9 | 0 |
| `lib/shell/`（`privacy_lock_view`、`mcp_tool_inventory_view`） | 2 | 17 | 1 |
| `lib/components/`（`markdown_view`、`password_display`） | 2 | 7 | 0 |
| `lib/` 根级 9 个独立工具总入口 | 9 | 117 | 26 |

**构建与工具链：**
- `analysis_options.yaml`：新增自定义 lint 规则或接入扫描脚本。
- CI / `flutter analyze`：新规则若为 error 级会阻断构建，需确认存量清理完毕后再提升级别。

**不变更：**
- `lib/theme/app_theme.dart` 的 token 值、`ThemeData` 配置、`ThemeContextExtension`。
- 深色模式下的任何视觉表现。
- 任何业务的 API、数据层、存储格式。
