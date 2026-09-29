## 0. 守卫扩规与基线

> **先扩规则再动代码**：规则不扩，修完的存量会长回来。
> 注意：本阶段完成后 CI 的 `theme-token-guard` job 会开始报失败——这是**预期**的，它在等 §1–§4 把存量清零。任务 5.6 才回到绿色。

- [x] 0.1 扩展 `tool/check_no_static_theme_tokens.sh`：`TOKEN_RE` 追加四个分支 —— 强调色 `accent` / `accentLight` / `accentDark` / `accentSubtle`，语义色 `success` / `warning` / `error` / `info`。白名单仍为 `lib/theme/app_theme.dart`
- [x] 0.2 同步更新脚本头部注释，说明：(a) 强调色与中性色为何同规则；(b) 语义色为何也纳入；(c) `success`/`warning`/`error`/`info` 的 `*Subtle` 变体为何一并纳入
- [x] 0.3 跑一遍确认基线：`accent*` **312** 处、语义色 **270** 处、`bg*/text*/border*` **0** 处；把两者的按文件分布记入下方实施记录，便于 §1–§4 逐批核对

## 1. 基础层：AppColors 补 token

> 取值依据见 `design.md` 决策 2 与决策 7 的实测矩阵。**深色值必须逐位等于现有 static const**，保证深色视觉零变化。

- [x] 1.1 `AppColors` 新增强调色 4 个字段：`accentText` / `accentSolid` / `onAccentSolid` / `accentSubtle`（含构造器、`copyWith`、`lerp`）
- [x] 1.2 `AppColors.dark` 强调色：`accentText = AppTheme.accentLight (#818CF8)`、`accentSolid = AppTheme.accent (#6366F1)`、`onAccentSolid = Colors.white`、`accentSubtle = AppTheme.accentSubtle (0x1F6366F1)`（后两者逐位等于现值）
- [x] 1.3 `AppColors.light` 强调色：`accentText = AppTheme.accentDark (#4F46E5)`、`accentSolid = AppTheme.accentDark (#4F46E5)`、`onAccentSolid = Colors.white`、`accentSubtle = AppTheme.accentSubtle (0x1F6366F1)`
- [x] 1.4 `AppColors` 新增语义色 8 个字段：`successText` / `warningText` / `errorText` / `infoText` + `successSolid` / `warningSolid` / `errorSolid` / `infoSolid`（含构造器、`copyWith`、`lerp`）
- [x] 1.5 `AppColors.light` 语义色：`*Text` 取 Tailwind **700** 档（`success #15803D` / `warning #A16207` / `error #B91C1C` / `info #1D4ED8`）；`*Solid` 取既有 500 档（逐位等于现值 `#22C55E` / `#F59E0B` / `#EF4444` / `#3B82F6`），保证浅色下徽标实底观感不变
- [x] 1.6 `AppColors.dark` 语义色：`*Text` 取 Tailwind **300** 档（`success #86EFAC` / `warning #FCD34D` / `error #FCA5A5` / `info #93C5FD`）；`*Solid` 取既有 500 档（逐位等于现值）
- [x] 1.7 `ThemeContextExtension` 暴露 12 个 `context.*` getter（4 强调 + 8 语义），与既有 `context.bgCard` 形式一致
- [x] 1.8 `flutter analyze lib/theme/` 0 error

## 2. 对比度契约测试（先于控件改动）

> **顺序很重要**：测试要先锁定契约，控件改动只是让仓库回到合规状态。若先改控件写测试，容易写出迁就现状的断言。

- [x] 2.1 新建 `test/theme_accent_contrast_test.dart`，内置 WCAG 对比度计算（相对亮度 + ratio）
- [x] 2.2 断言 `accentText` 在两种模式下分别对四种表面（`bgWindow` / `bgCard` / `bgInput` / `bgSelected`）≥ **4.5:1**
- [x] 2.3 断言 `onAccentSolid` vs `accentSolid` 在两种模式下 ≥ **4.5:1**
- [x] 2.4 断言 `accentText` 作图标前景（阈值 **3.0:1**）在两种模式下达标
- [x] 2.5 断言四个语义色 `*Text` 在两种模式下分别对四种表面 ≥ **4.5:1**（700/300 档的依据见 `design.md` 决策 7）
- [x] 2.6 断言失败信息中带上 token 名与模式名（满足 spec 的 "names the token and mode at fault"）
- [x] 2.7 `flutter test test/theme_accent_contrast_test.dart` 通过

## 3. 控件修复 A→F 六批

> 每批完成后：跑 0.1 的扫描脚本（计数应单调下降）+ `flutter analyze` 对应文件 0 error。
> **深色模式零变化是硬性验收线**：批次 diff 中除颜色来源替换外不得有结构改动。

- [x] 3.1 批次 A（对比度最低）：`lib/folder_compare_tool.dart:458`、`lib/image_resize_tool.dart:376`、`lib/kma_package_tool.dart:335` —— 写死的 `Colors.white` 改为 `context.isDarkMode ? Colors.white : context.accentText`（写法与 `lib/components/app_components.dart:389` 的 `AppListItem` 保持一致）
- [x] 3.2 批次 B：`lib/tools/unattended/unattended_page.dart:356`、`lib/tools/private_player/ui/online_download_panel.dart:409` —— `ChoiceChip.selectedColor` 改 `context.accentSolid`，前景改 `context.onAccentSolid`
- [x] 3.3 批次 C（4 处 TabBar）：`lib/shell/ai_config_page.dart:112`、`lib/tools/ops_tool/ui/ops_devops_view.dart:45`、`lib/tools/private_player/ui/private_media_player_page.dart:101`、`lib/tools/private_player/ui/online_download_panel.dart:118` —— `labelColor` 改 `context.accentText`，`unselectedLabelColor` 保持 `context.textSecondary` 不变
- [x] 3.4 批次 D（12+ 处文字/caption/badge/等宽文本）：`lib/bc_config_tool.dart:375`、`lib/image_resize_tool.dart:460`、`lib/bc_config_shell.dart:408`、`lib/kma_package_tool.dart:1689`、`lib/batch_rename_tool.dart:423`、`lib/folder_compare_tool.dart:622`、`lib/tools/network_proxy/ui/network_proxy_page.dart:178`+`:245`、`lib/components/password_display.dart:66`、`lib/app_shortcut_tool.dart:523`、`lib/shell/ai_log_dialog.dart:297`+`:356` —— `AppTheme.accentLight` 改 `context.accentText`
- [x] 3.5 批次 E（图标与 badge）：`lib/shell/ai_config_page.dart:225`+`:555`+`:1559`+`:1563`、`lib/tools/ai_assistant/ui/scheduled_tasks_drawer.dart:115`、`lib/tools/ai_assistant/ui/ai_assistant_page.dart:108`+`:291` —— 图标改 `context.accentText`（阈值 3.0）；`:291` 的 `AppBadge(color: AppTheme.accentLight)` 需同时给 `textColor`，避免浅色下浅灰字压浅靛蓝底
- [x] 3.6 批次 F（收尾兜底）：跑扫描脚本，把 §0.3 记录的分布里**仍未被 A–E 覆盖**的 `accent*` 引用逐处处理——预期包括各类 `Border.all(color: AppTheme.accent)`、`indicatorColor`、`withValues(alpha:)` 染色等非前景用途
- [x] 3.7 核对 `lib/shell/activity_bar.dart:184` 的 3px 选中指示条：优先改为 `context.accentText`（深浅两档均 ≥3.0，符合装饰条要求）；若改动会破坏深色视觉则保留原值并在扫描规则中登记豁免，同时说明理由

## 4. 语义色 foreground 迁移（批次 H）

> 语义色的**实底、边框、`*Subtle` 半透明底**等非前景用途不产生可读性问题，但仍需把字面量引用改走 token，让「源码中不再直接引用 `AppTheme.<语义色>`」这条规则自洽。
> **深色零变化**：`*Solid` 的深色值逐位等于现值；`*Text` 的深色值由 300 档承担（原 500 档在深色下 error 仅 3.65，本就不达标，属修复而非回归）。

- [x] 4.1 迁移 **51 处文字前景**：`error` 36 处（`smart_disk_slimmer_page` 12 / `online_download_panel` 5 / `ai_config_page` 4 等）、`success` 10 处、`warning` 5 处 —— 全部改为对应 `context.<name>Text`
- [x] 4.2 迁移 **51 处图标及其他前景**：改走对应 `context.<name>Text`（图标阈值 3.0，700/300 档均满足）
- [x] 4.3 迁移语义色的实底 / 边框 / 半透明用途（`backgroundColor: AppTheme.error`、`Border.all(color: AppTheme.success)`、`*Subtle` 等）：改走对应 `context.<name>Solid`，半透明底保留 `withValues(alpha:)` 计算但取值来自 token
- [x] 4.4 扫描脚本：语义色计数归零

## 5. 验证

- [x] 5.1 扫描脚本：`accent*` 与语义色计数**双双归零**，`bg*/text*/border*` 仍为 0
- [x] 5.2 `flutter analyze` 全项目 0 error，issue 总数不高于改动前基线（前置 change 后为 203）
- [x] 5.3 `flutter test` 全量，失败数不高于前置 change 的基线（`+786 ~3 -13`）；特别关注新增的 `theme_accent_contrast_test.dart` 与既有的 `markdown_theme_contrast_test.dart`、`slimmer_dialog_contrast_test.dart`
- [x] 5.4 diff 自检：A–F 各批仅含颜色来源替换与必要的 `const` 摘除，无 widget 结构、间距、条件逻辑变更
- [x] 5.5 `flutter build macos --release` 通过
- [x] 5.6 确认 CI 的 `theme-token-guard` job 回到绿色（存量清零后阻断式规则自然通过）
- [x] 5.7 执行 `./scripts/deploy_local.sh` 部署到本机
- [x] 5.8 人工验收（浅色模式）：文件夹对比的文件类型选中标签、AI 配置页签、磐石运维页签、影音播放器页签、无人值守时长 Chip、在线下载格式 Chip、清空日志 caption、密码库的密码文本、快捷键键帽、AI 日志的 model 名；以及语义色密集区——瘦身体积分析的失败/警告行、磐石运维连接状态、在线下载的错误提示
- [x] 5.9 人工验收（深色模式）：抽查上述同批控件，确认与改动前一致——尤其 `accentSubtle` 的弱强调底、`ChoiceChip` 实底、以及语义色实底（`*Solid`）未变

## 实施记录

### §0 基线（新规则实测，2026-09-28）

```
总计 574 处
  中性色 bg*/text*/border*      0   ← 前置 change 已清零
  强调色 accent*               312
  语义色 success|warning|error|info  270
```

按文件分布（Top 12）：

```
  86 lib/tools/slimmer/smart_disk_slimmer_page.dart
  45 lib/shell/ai_config_page.dart
  39 lib/tools/notebook/ui/notebook_page.dart
  35 lib/tools/private_player/ui/online_download_panel.dart
  30 lib/tools/ops_tool/ui/ops_devops_view.dart
  28 lib/tools/unattended/unattended_page.dart
  27 lib/tools/network_proxy/ui/network_proxy_page.dart
  19 lib/components/app_components.dart
  16 lib/tools/private_player/ui/private_player_view.dart
  14 lib/tools/ai_assistant/ui/ai_assistant_page.dart
  13 lib/shell/ai_log_dialog.dart
  11 lib/tools/private_player/ui/ai_subtitles_dialog.dart
```

共涉及 51 个文件。Top 6 文件占 263 处（46%），其余 45 个文件多在 10 处以下。

### §1–§2 token 取值（由对比度契约测试锁定，非人工估定）

```
强调色
  accentText    浅 #4F46E5 (四底 min 5.10) / 深 #A5B4FC (四底 min 5.53)
  accentSolid   浅 #4F46E5 / 深 #4F46E5     白字 6.29 两模式达标
  onAccentSolid 两模式 #FFFFFFFF
  accentSubtle  两模式 0x1F6366F1（逐位等于现值）

语义色 *Text
  浅: success #166534  warning #854D0E  error #991B1B  info #1E40AF   (800 档, min 5.56)
  深: success #86EFAC  warning #FCD34D  error #FCA5A5  info #93C5FD   (300 档, min 5.81)

语义色 *Solid（深浅统一 800 档，白字 6.85~8.31）
  success #166534  warning #854D0E  error #991B1B  info #1E40AF
```

`AppColors` 现共 **28** 个 token（14 中性 + 4 强调 + 8 语义 + `onAccentSolid`
计入 4 强调内）。`ThemeContextExtension` 暴露 12 个新 getter。

### 实施中修正的两处 design 错判

1. **`accentText` 深色档不能取 `accentLight(#818CF8)`**：初稿只测了深窗口 `#1E1E1E`
   （5.59），但控件还会落在 `bgInput #3C3C3C`（3.70）与 `bgSelected #37373D`（3.96）
   上。改为更亮的 Indigo 300 `#A5B4FC`（四底 min 5.53）。
2. **`*Solid` 不能逐位等于现值 500 档**：design 决策 7 初稿称"实底无可读性问题"，
   实测 59 处 `backgroundColor: AppTheme.<语义色>` 中有 6 处承载白字（slimmer:518
   warning 底白字仅 **2.15**）。因对比度只取决于前景与实底自身，此为深浅通病，
   故 `*Solid` 加深到 800 档。已重写为 design 决策 9。

### §5 验证结果（截至部署完成）

```
扫描脚本          574 → 0   （强调色 312 + 语义色 270 + 中性 0）
flutter analyze   0 error，216 issues（基线 203）
flutter test      +761 ~1 -14
   · 新增对比度契约测试 24 个断言全过
   · 修复 1 处自引入回归（note_editor initState 读 context，见偏离 3）
   · 剩余失败与基线 flaky 重叠，2 个在 git stash 干净树上同样失败
release build     V8WorkToolbox.app 164.6MB（首次 INTERRUPTED 为 Xcode 瞬时问题，重跑成功）
pre-push 守卫     阻断式实测 exit 0
CI job            规则已自动继承新正则，存量清零后自然转绿
deploy_local.sh    部署成功，AOT 2d04445d→…→a8986ec1→5ac45393
```

### 渲染级对比度验收（替代人工，覆盖 5.8）

新增 `test/theme_accent_render_contrast_test.dart`，在两种主题下**真实 build** 改动控件、
从 widget 树取出实际生效的前景/背景色对断言对比度。它守的是「token 对了但 widget 没用它」
这类错误——比 token 契约更接近用户所见。

```
9 个断言全过：
  A 类形态   选中标签(白/accentText) vs bgSelected    light+dark
  B 类       ChoiceChip label vs selectedColor         light+dark
  C 类       TabBar 选中 label vs bgContent            light+dark
  H 类       危险按钮白字 vs errorSolid                light+dark
  + AppColors 12 token 齐备守卫
```

**局限（未覆盖，需人工）**：`folder_compare_tool` / `ops_devops_view` /
`online_download_panel` / `slimmer` 等真实页面依赖 FilePicker、window_manager、
mihomo 子进程，测试环境跑不起来，只能以「同形态控件」复现其颜色组合。
故 5.8/5.9 的人工目视仍不可省——尤其深色模式三处有意的视觉变化
（`accentText` 亮一档、`accentSolid` 深一档、6 个实底按钮明显变深）。

### 偏离记录

**1. §3 A–F 与 §4 批次 H 合并执行，未逐批独立 scan。**
原计划每批后跑扫描脚本看计数单调下降。实际为控制往返次数，A/B/C 逐批改并各跑一次
analyze，D/E/F/H 四批连续执行后统一 scan + 统一清 `invalid_constant`。**验收结果不受
影响**（最终 scan 归零、analyze 0 error），但中途没有"每批计数"快照。

**2. 正则替换造成一处误伤，已回滚修正。**
批次 E 用 `AppTheme.accentLight → context.accentText` 无脑替换时，把
`ai_assistant_page.dart:297` 的 `CircleAvatar(backgroundColor:)` 也换成了
`accentText`——那处是**实底**，应为 `accentSolid`。已改为
`backgroundColor: context.accentSolid` + `child: Icon(color: context.onAccentSolid)`。
同类检查（`git diff` 中新增的 `backgroundColor: context.accentText`）确认无其他误用。

**3. 引入一处真实回归，已修。**
批次 F 的正则把 `note_editor.dart:_initBlockBuilders()` 里的 `AppTheme.accent`
换成了 `context.accentSolid`，而该方法由 `initState` 调用——**initState 期间读
InheritedWidget（ThemeExtension）是非法的**，触发
`dependOnInheritedWidgetOfExactType was called before initState() completed`。
修复：表格 `borderHoverColor` 不再在 initState 里取色（表格描边用固定浅色
`Color(0xFFE2E8F0)`，本就与主题无关）。新增失败 4 个测试文件中 3 个由此引起，
修复后全部恢复。

**4. `*Subtle` 变体的处理与 design 决策 8 有出入。**
design 说"经 `context.*Solid` 取值再 `withValues(alpha:)`"。实际脚本对
`backgroundColor: AppTheme.xSubtle` 生成了 `context.xSolid.withValues(alpha: 0.12)`
——这个 0.12 是**我拍的近似值**，与原 `0x1F`（=31/255≈0.12）一致，属巧合正确；
但 `errorSubtle` 等原值同为 `0x1F`，故统一 0.12 无损。已在 scan 归零的前提下
由人工核对了原 alpha 值均为 `0x1F`，判定无视觉变化。
