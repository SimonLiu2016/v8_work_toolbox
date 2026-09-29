## Why

`refactor-unified-theme-system` 与 `clean-up-tool-page-static-theme-tokens` 已把 14 个中性表面色（`bg*` / `text*` / `border*`）全部接入 `AppColors` `ThemeExtension`，但**强调色系列仍停留在 `AppTheme` 的 static const**（`accent` / `accentLight` / `accentDark` / `accentSubtle`），浅深模式共用同一组值，且没有定义实底之上的前景色。

结果是浅色模式下 20 组控件不可读：选中态标签白字落在浅底上（对比度 1.10，白底白字）、页签 `labelColor` 用 `accentLight`（2.85）、「清空日志」等 caption 用 `accentLight` 落在 `bgInput` 上（2.72）。用户已在「文件夹对比 → 文件类型」选中标签上实测到该问题。

已用 `git stash` 对照确认这些问题不是 L1/L2 引入的，而是 L2 tasks.md §5 明确划出的边界——那两条 change 的 spec 写的是「颜色来源动态化」，没有覆盖「强调色需按主题提供达标前景」。

## What Changes

- **在 `AppColors` 中补齐强调色系列**（4 个新 token）：
  - `accentText`：强调色前景文字。浅色 `#4F46E5`（6.01）/ 深色 `#818CF8`（5.59）
  - `accentSolid`：强调色实底。浅色 `#4F46E5` / 深色 `#6366F1`
  - `onAccentSolid`：实底之上的前景色（含图标）。两种模式均为白色；浅色下对比度由实底加深到 `#4F46E5` 保证（6.29）
  - `accentSubtle`：从 static const 迁入 ThemeExtension，成为按主题定义的弱强调底
- **在 `AppColors` 中补齐语义色系列**（8 个新 token）：`successText` / `warningText` / `errorText` / `infoText` + `successSolid` / `warningSolid` / `errorSolid` / `infoSolid`
  - `*Text`：语义色前景文字与图标。浅色取 Tailwind **700** 档、深色取 **300** 档——因为 500 档在浅色下 1.85–3.76（`success` 仅 1.85），在深色下 `error` 也只有 3.65，两头都不达标
  - `*Solid`：语义色实底与半透明底。两模式均取既有 500 档（逐位等于现值），保证徽标/边框观感不变
- **暴露 `context.accentText` / `context.accentSolid` / `context.onAccentSolid` / `context.accentSubtle`**，与既有 `context.bgCard` 等 getter 形式一致。
- **修复 20 组控件**（18 个文件），按 contrast 从低到高排序分批推进，每批独立可验证。
- **扩展 `tool/check_no_static_theme_tokens.sh`**：把 `accent` / `accentLight` / `accentDark` / `accentSubtle` 也纳入匹配规则（保留白名单），阻止第 312 处之后再生出新引用。当前该规则对这批引用完全失效。
- **新增对比度契约测试** `test/theme_accent_contrast_test.dart`：把每个新 token 在两种模式下的对比度固化为断言（文字 ≥4.5，图标 ≥3.0，实底上前景 ≥4.5），防止未来调色回归。

**非目标：**
- 不评估 `AppColors`(14+12 token) 向 Material 3 `ColorScheme` 的迁移，该议题继续独立。
- 不调整既有任何中性色 token 的值。
- 不给工具页补充新的浅色专属视觉设计。

## Capabilities

### New Capabilities

- `theme-accent-contrast`: 定义强调色系列在各主题模式下的对比度契约，包括强调前景文字、强调实底、实底之上的前景、弱强调底色四类角色在浅色与深色模式下的最低对比度要求与取值来源。

### Modified Capabilities

- `theme-and-brand`: 扩展「Dynamic theme inheritance for reusable components」需求，把强调色系列纳入动态继承范围（此前只覆盖中性表面色），并补充一个「源码中不存在静态强调色引用」的可验证场景。
- `shared-markdown-theme-contrast`: 无需求变更。该 capability 的 `NotebookLightScope` 使用裸 `ThemeData.light()`，本次确认其在浅色容器内不依赖强调色 token，行为不变——此处列出仅为说明已核查，不产生 delta。

## Impact

**代码 — 基础层（1 个文件）：**

| 文件 | 改动 |
|---|---|
| `lib/theme/app_theme.dart` | `AppColors` + 12 token、light/dark 两套 preset、`lerp`、`ThemeContextExtension` +12 getter |

**代码 — 控件层（18 个文件，20 组）：**

| 组 | 类别 | 文件:行 | 当前对比度 |
|---|---|---|---|
| A1 | 选中标签白字 | `lib/folder_compare_tool.dart:458` | 1.10 |
| A2 | 选中标签白字 | `lib/image_resize_tool.dart:376` | 1.23 |
| A3 | 选中标签白字 | `lib/kma_package_tool.dart:335` | 1.23 |
| B1 | ChoiceChip | `lib/tools/unattended/unattended_page.dart:356` | 4.47 |
| B2 | ChoiceChip | `lib/tools/private_player/ui/online_download_panel.dart:409` | 4.47 |
| C1 | TabBar | `lib/shell/ai_config_page.dart:112` | 2.85 |
| C2 | TabBar | `lib/tools/ops_tool/ui/ops_devops_view.dart:45` | 4.08 |
| C3 | TabBar | `lib/tools/private_player/ui/private_media_player_page.dart:101` | 4.08 |
| C4 | TabBar | `lib/tools/private_player/ui/online_download_panel.dart:118` | 4.08 |
| D1 | caption | `lib/bc_config_tool.dart:375`、`lib/image_resize_tool.dart:460`、`lib/bc_config_shell.dart:408` | 2.72 |
| D2 | caption | `lib/kma_package_tool.dart:1689` | 2.72 |
| D3 | caption | `lib/batch_rename_tool.dart:423` | 2.72 |
| D4 | caption | `lib/folder_compare_tool.dart:622` | 2.72 |
| D5 | badge | `lib/tools/network_proxy/ui/network_proxy_page.dart:178`、`:245` | 2.40 |
| D6 | 等宽文本 | `lib/components/password_display.dart:66` | 2.72 |
| D7 | 键帽 | `lib/app_shortcut_tool.dart:523` | 2.72 |
| D8 | 文字/链接 | `lib/shell/ai_log_dialog.dart:297`、`:356` | 2.98 |
| E1 | 标题栏图标 | `lib/shell/ai_config_page.dart:225`、`lib/tools/ai_assistant/ui/scheduled_tasks_drawer.dart:115`、`lib/ai_assistant_page.dart:108` | 2.85 |
| E2 | NEW badge | `lib/tools/ai_assistant/ui/ai_assistant_page.dart:291` | 2.60 |
| E3 | 序号/文字 | `lib/shell/ai_config_page.dart:555`、`:1559`、`:1563` | 2.85–2.98 |

**已核查确认安全、不在本次范围：** 28 处 `Colors.white` 前景（视频黑底、播放器遮层、accent/error/warning 实底、深色浮层），以及 `lib/shell/activity_bar.dart:184` 的 3px 选中指示条（装饰条，非文字，深浅皆成立）。

**工具链：**
- `tool/check_no_static_theme_tokens.sh`：正则扩到 `accent*` **与语义色** `success`/`warning`/`error`/`info`，白名单仍是 `lib/theme/app_theme.dart`。当前该规则对这两批共 582 处引用完全失效。
- 语义色非前景用途（实底、边框、`*Subtle` 半透明底）虽无可读性问题，也一并迁走字面量，使规则自洽。
- `test/theme_accent_contrast_test.dart`：新增（含语义色 8 token 的对比度断言）
- `.github/workflows/build-release.yml`：`theme-token-guard` job 自动继承新规则，无需改

**不变更：**
- 深色模式下任何控件的视觉表现（所有浅色专用取值仅在 `AppColors.light` 中定义）
- 业务的 API、数据层、存储格式
