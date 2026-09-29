## Context

`clean-up-tool-page-static-theme-tokens` 已把 671 处中性色静态引用清零，并把守卫规则固化在 `tool/check_no_static_theme_tokens.sh`。但该规则的正则只覆盖 `bg*` / `text*` / `border*`，**`accent*` 系列 312 处引用完全在规则之外**，且仍在 `AppTheme` 的 static const 上，浅深共用同一组值。

已用 `git stash` 对照确认：这 20 组问题在两条前置 change 之前就存在，不是回归。

动机见 `proposal.md` — Why；对比度契约见 `specs/theme-accent-contrast/spec.md`。

## Goals / Non-Goals

**Goals:**
- 强调色系列补齐为 ThemeExtension token，4 个角色各按模式取值。
- 20 组控件全部改走 `context.*`，浅色模式达标、深色模式视觉零变化。
- 守卫规则扩到 `accent*`，否则修完会长回来。
- 对比度契约固化为测试。

**Non-Goals:**
- 不评估 `AppColors`(14+12 token) → Material 3 `ColorScheme` 迁移（继续独立）。
- 不调整任何中性色 token 的值。
- 不给工具页补新的浅色专属设计。
- 不重做深色模式的视觉（中性色与 `accentText` 的深色值逐位等于原行为）。**例外**：`*Solid` 加深到 600 档与 `*Text` 改用 300 档会改变深色下的语义色外观，这是决策 7/9 的有意修复，不算违约。

## Decisions

### 1. 新增 4 个 token，而非改造现有 4 个 static const

- **Decision**：`AppColors` 新增 `accentText` / `accentSolid` / `onAccentSolid` / `accentSubtle`；保留 `AppTheme.accent` 等 static const 作为**定义源**（与 `bgCard` 等的处理完全一致）。
- **Rationale**：与 L1 建立的模式同构——static const 是 preset 的定义处，widget 层只读 extension。若反过来把 static getter 改成查 `SettingsStore`，会退回 L1 明确否决的方案（破坏 Flutter 响应式重建）。
- **Alternatives Considered**：
  - *直接改 `AppTheme.accent` 的值*：不改结构、改动最小。但浅深共用同一个字段就不可能同时达标（见决策 2），等于没修。
  - *引入 `ColorScheme` 的 `primary` / `onPrimary` / `primaryContainer` / `onPrimaryContainer`*：Material 3 语义更标准，但这是个独立的大迁移（L1 已在 Open Questions 里记着），本次不做，避免 scope 爆炸。

### 2. 四个角色的取值必须分离，不能用同一颜色

- **Decision**：
  ```
  角色           浅色            深色            为什么不能共用一个值
  accentText     #4F46E5        #818CF8         同一个值必有一头不达标
  accentSolid    #4F46E5        #6366F1         浅色下需加深以承载白字
  onAccentSolid  #FFFFFF        #FFFFFF         白字在两种实底上都达标
  accentSubtle   按模式重定义    按模式重定义     当前 0x1F6366F1 是写死的靛蓝
  ```
- **Rationale**：实测矩阵（对比度，计算脚本见 tasks.md §0）：
  ```
                   vs 浅窗口   vs 浅选中底   vs 深窗口
  accent #6366F1      4.27        3.62         3.73
  accentLight #818CF8 2.85        2.42         5.59
  accentDark #4F46E5  6.01        5.10         2.65
  ```
  `accentDark` 与 `accentLight` 分别是两种模式的最优解，且**在对方模式下的得分都低于 4.5**。这是"必须分角色 + 分模式"的硬证据，不是审美选择。
- **Trade-off**：`accentSolid` 浅色用 `#4F46E5` 而非 `#6366F1`，会让浅色模式下选中 chip 的底色比原来更深、更"重"。这是为白字 4.5:1（`#FFFFFF` vs `#4F46E5` = 6.29）付的代价；若沿用 `#6366F1`，白字只有 4.47，即 B 类那两处仍不达标。

### 3. B 类修法：加深实底，而不是给白字换色

- **Decision**：B1/B2 两处 `ChoiceChip(selectedColor: accent)` 保留白字，只把 `selectedColor` 改为 `context.accentSolid`。
- **Rationale**：Chip 是"实底 + 白字"的既有形态，白字 6.29:1 达标。另一条路是把 Chip 改成浅底深字（`selectedColor: context.bgSelected` + 前景 `accentText`），但会改变深色模式下的 Chip 形态——而用户要求深色视觉不变。
- **Alternatives Considered**：浅底下把白字改成 `accentText`。否决——白字压 `#6366F1` 已经 4.47，换成深靛蓝字反而更差。

### 4. A 类修法：改前景，不改容器

- **Decision**：A1/A2/A3 的容器（`bgSelected` / `bgInput` / `accentSubtle`）保持不动，只把写死的 `Colors.white` 改为 `context.accentText`。
- **Rationale**：容器本身是浅色模式下正确的选中指示（用户没抱怨底色不对），错的只是前景。改容器会连带影响边框、hover 等一串状态。
- **深色模式不变如何保证**：`AppColors.dark.accentText = #818CF8`，而这 3 处的深色前景原本就是 `Colors.white`。这里**不成立**——所以这 3 处必须显式处理：`context.isDarkMode ? Colors.white : context.accentText`，或统一用 `context.accentText` 但把深色值也设成白。
  - **最终采用**：`AppColors.dark.accentText = #FFFFFF` 不成立（那会让深色下的 accent 文字全变白，破坏 D 类 12 处的强调语义）。故 A 类这 3 处改用 `context.onSelected` 语义——不，更简单：**A 类容器的深色值本来就是深色**（`bgSelected #37373D`），白字在深色下是 11.82:1 正确的。所以 A 类正确写法是 `context.isDarkMode ? Colors.white : context.accentText`。
  - 这与 `lib/components/app_components.dart:389` 的 `AppListItem` 和 `lib/shell/settings_dialog.dart:256` 的既有写法完全一致——**代码库里已经有这个正确模式，A 类只是没用**。

### 5. E 类按图标阈值 3.0 而非 4.5 验收

- **Decision**：E1（3 个标题栏 20–22px 图标）按 ≥3.0 验收；E2/E3（含文字与 badge）按 4.5。`activity_bar:184`（3px 指示条）同样按 3.0，改用 `context.accentText`。
- **Rationale**：WCAG 1.4.11 对非文字对比度要求 3.0。指示条虽属纯装饰，但改用 token 不增加成本且让守卫规则无豁免缺口。
- **Open Question 已收口**：`accentText` 深色值 `#818CF8` 在深色表面上 5.59，浅色 `#4F46E5` 在浅色表面上 6.01——**两个模式都超过 3.0**，所以图标直接用 `context.accentText` 即可，不需要额外图标专用 token。

### 6. 守卫规则一次性扩齐，而非本次只加用到的

- **Decision**：`tool/check_no_static_theme_tokens.sh` 的 `TOKEN_RE` 加入 8 个分支——强调色 `accent` / `accentLight` / `accentDark` / `accentSubtle`，语义色 `success` / `warning` / `error` / `info`（含各自的 `*Subtle`），并**同步更新脚本头部的规则说明**。
- **Rationale**：若只禁 `accentLight`（本次修得最多），下次有人写 `AppTheme.accent` 仍然畅通；同理只禁强调色不禁语义色，会留下 270 处的规则缺口。规则要么完整要么不设。

## Risks / Trade-offs

- **[Risk] `*Solid` 加深到 600 档会改变**两种模式**下 6 处实底按钮的外观（不只是浅色）**：
  → *Mitigation*：这是对比度只取决于前景与实底自身所致，无法靠分模式规避。白字从 2.15–3.76 提升到 3.30–4.92，属必要的可读性修复。**需用户人工验收**这 6 个按钮（删除/粉碎/彻底清空/安全移入废纸篓/保存/确定）变深是否可接受。

- **[Risk] `accentSolid` 浅色加深后，浅色模式下选中态整体变重**：
  → *Mitigation*：这是 B 类两处 ChoiceChip 的局部影响，共 2 个控件。已在 spec 中把"实底 + `onAccentSolid`"定义为独立角色，未来若要调浅可在不改结构的前提下只改 `accentSolid` 一个值。**需用户人工验收确认可接受**。

- **[Risk] `accentSubtle` 从 static const 迁入 extension 后，深色下的弱强调底会变**：
  → *Mitigation*：`AppColors.dark.accentSubtle` 必须逐位等于 `AppTheme.accentSubtle`（`0x1F6366F1`），保证深色零变化；浅色可用同值或微调。**验收线：深色模式下所有原 `accentSubtle` 使用者视觉不变**。

- **[Risk] 20 组控件散在 18 个文件，逐组人工验证成本高**：
  → *Mitigation*：按 contrast 从低到高分批（A→B→C→D→E），每批改完立即跑扫描脚本 + analyze；最后用对比度契约测试做整体兜底。**不逐组截图**——改为测试断言 + 末尾一次人工抽查。

- **[Risk] D 类 6 处「清空日志」是同一模式的复制粘贴，可能漏改**：
  → *Mitigation*：扫描脚本归零即为漏改的判据。若脚本报 0 而仍有漏改，说明正则没覆盖到，那就修正则而不是放过。

- **[Trade-off] `context.isDarkMode ? Colors.white : context.accentText` 这个三元在 A 类重复 3 次**：
  → *Mitigation*：可接受。提取成共享 helper 需要新的公共组件，而 A 类只有 3 处；`app_components.dart` 与 `settings_dialog.dart` 已有同样的内联写法，保持一致比抽象化更重要。

## Migration Plan

1. 先扩 `tool/check_no_static_theme_tokens.sh` 规则并跑出基线（`accent*` **312** 处、语义色 **270** 处）。守卫已是阻断式（前置 change 4.6），此时 CI 会失败——这是预期的，记录基线即可。
2. 改 `lib/theme/app_theme.dart`：加 12 token、两套 preset、`lerp`、12 个 `context.*` getter。
3. 写 `test/theme_accent_contrast_test.dart` 并跑通——**在改任何控件之前**。这样测试先锁定契约，控件改动只是让仓库回到合规状态。
4. 按 A→B→C→D→E→F 六批改控件，再接语义色批次 H，每批后跑扫描 + analyze，计数应单调下降。
5. 两类计数均归零 → analyze 0 error → 全量 test → release 构建 + 部署。
6. 回滚策略：每批独立 commit，任一批出问题 `git revert` 那一批。

## Decisions（续）

### 7. 语义色一并纳入（范围扩大）

- **Decision**：语义色系列与强调色同样处理——`AppColors` 新增 `successText` / `warningText` / `errorText` / `infoText` + 四个 `*Solid`；守卫规则同步扩到 `success`/`warning`/`error`/`info`。
- **Rationale**（实测矩阵，四种浅色表面 = 窗口 #F8FAFC / 卡片 #FFFFFF / 输入 #F1F5F9 / 选中 #E2E8F0）：
  ```
  色名        500 档浅色 min   500 档深色 min
  success     1.85            4.84
  warning     1.74            5.14
  error       3.05            2.93   ← 深色下也不达标
  info        2.98            3.00   ← 深色下也不达标
  ```
  500 档是**两头失真**，不是浅色单侧问题。且语义色共 270 处引用（前景 102 处），与强调色同源同病，分开处理会让守卫规则出现"禁了一半"的中间态。
- **取值**：`*Text` 浅色取 Tailwind **700** 档（`#15803D` / `#A16207` / `#B91C1C` / `#1D4ED8`，浅色 min 4.07–5.44），深色取 **300** 档（`#86EFAC` / `#FCD34D` / `#FCA5A5` / `#93C5FD`，深色 min 5.81–7.86）。700 档在浅选中底上 4.07 略低于 4.5，但语义色文字的 51 处几乎全是 badge/状态行而非正文长文，按"≥4.5 或退一步 ≥3.0 可读"处理；测试统一按 4.5 断言，若有少数确实只到 4.07 的用例，在测试中单独标注该组合并按 3.0 断言（**不允许悄悄放宽阈值**，必须在测试里写明理由）。
  `*Solid` 取**加深档**而非现值 500 档。原因见决策 9：500 档上压白字仅 2.15–3.76，深浅通病。
  `*Solid` 取 600 档（`#16A34A` / `#CA8A04` / `#DC2626` / `#2563EB`），白字在其上 3.30–4.92。
  这会**改变深浅两种模式下的实底按钮外观**（比原来更深），属有意的可读性修复，不是零变化——
  已在 Risks 中显式记录。
- **深色零变化如何保证**：`*Solid` 深色值逐位等于现值；`*Text` 深色值从 500 档改为 300 档是**有意的修复**（500 档在深色下 error 仅 3.65），已在本 change 的 Why 中说明，不算回归。

### 8. `*Subtle` 变体一并纳入规则

- **Decision**：`successSubtle` / `warningSubtle` / `errorSubtle` / `infoSubtle` 也纳入扫描规则并迁走字面量，但它们**不进 `AppColors`**，仍保留 static const。
- **Rationale**：`*Subtle` 是半透明底（`0x1F22C55E` 之类），深浅模式下叠加效果不同但都不产生可读性问题；为四个值新增 4 个 token 只会让 `AppColors` 更臃肿。迁走字面量的方式是经 `context.*` 取实底色再 `withValues(alpha:)`，而不是新增 token。

### 9. 语义色实底需加深（修正决策 7 的错判）

- **Decision**：`*Solid` 从现值 500 档改为 600 档（`success #16A34A` / `warning #CA8A04` / `error #DC2626` / `info #2563EB`）。
- **Rationale**：决策 7 初稿写"实底无可读性问题，逐位等于现值"，**这是错的**。实测共 **59 处** `backgroundColor: AppTheme.<语义色>`，其中 6 处是承载文字的实底按钮：
  ```
  password_page:134      FilledButton(bg: error)   → 白字 3.76
  slimmer:518            ElevatedButton(bg: warning)→ 白字 2.15  ← 最严重
  slimmer:1136           FilledButton(bg: error, fg: 白) → 3.76
  vocab_book:328/:675    FilledButton(bg: error)   → 3.76
  notebook_page:1329     ElevatedButton(bg: error) → 3.76
  ops_devops_view:615    ElevatedButton(bg: success)→ 2.28
  ```
  前景是 `FilledButton` / `ElevatedButton` 的默认白字（或显式 `Colors.white`）。**对比度只取决于前景与实底两者自身，与周围主题无关**——所以这是深浅通病的既存问题，不是浅色模式引入的。
- **为什么不改用深色字而非加深实底**：`warning500 #F59E0B` 上压深字（`#0F172A`）会是 8.7:1，比加深实底更达标。但按钮的"危险/确认"语义靠实底传达，深字黄底会读成普通次要按钮；且 6 处分散在删除/粉碎/清空等高危操作上，视觉一致性比省一步加深更重要。
- **Trade-off**：两模式下的实底按钮都会变深。深色模式下 `error600 #DC2626` 比原来的 `#EF4444` 更暗，与深色底的分离度略降。这是可读性与醒目度的取舍，取可读性。

## Open Questions

（本次无遗留 Open Questions。语义色已在决策 7 收口。）
