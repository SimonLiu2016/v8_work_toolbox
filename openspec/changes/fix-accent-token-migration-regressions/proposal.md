## Why

`unify-accent-tokens-and-fix-light-mode-contrast` 的批次 F 用一个"按用途分派"的正则把
剩余 264 处 `AppTheme.accent*` 批量迁到 `context.*`。该规则只识别了 `backgroundColor:` →
`*Solid`、`color:` → `*Text` 两个角色，**漏掉了第三类角色 `*Subtle`**——它是 12% 半透明底
（`0x1F22C55E` 等），设计意图是"淡底 + 深字"。

后果是用户实测发现的四类**功能性损坏**（不是美观问题）：

- 徽标/容器的底色与文字被映射到同一个实色，"只剩一个色块、看不见文字"（问题 2/3/4）
- 无人值守页左上角图标容器从淡绿底变成深绿实底，成了一个突兀的绿块（问题 1）
- `AppBanner` 四个分支底色改成实底但文字忘了同步改，深底压近黑字对比度 2.05（问题 5）

同一轮还暴露出一个 L1 引入的回归：密码工具独立窗口的
`WindowKind.passwordVault` 服务清单漏了 `..._settingsStore`，导致
`themeModeNotifier` 停在默认 `ThemeMode.system`，深色主题下该窗口仍渲染浅色（问题 6）。

四个问题的共同点：**它们都是"把可用状态改成不可用"的功能损坏，而非对比度微调**，
因此单独立项、优先于父 change 的人工验收收尾。

## What Changes

- **恢复 `*Subtle` 角色**：全部误映射处改为「半透明底 + 深字」的正确组合。底色经
  `context.<name>Solid.withValues(alpha: 0x1F / 255)` 派生（原 `0x1F` ≈ 0.1216，
  逐处核对原 alpha 均为 `0x1F`），文字用 `context.<name>Text`。
  这样两种模式下都是淡底深字，且深色模式下因 `*Text` 取 300 档仍可读。
- **修 `AppBanner` 四分支**：底色恢复半透明派生，文字维持 `context.textPrimary`
  ——文案较长，淡底深字比实底白字更耐读，且这是改动最小的一边。
- **修无人值守页左上角图标容器**：底色恢复半透明派生，图标色保持
  `context.<name>Text`，恢复到"淡底 + 图标"的原本形态。
- **补密码工具窗口服务初始化**：`WindowKind.passwordVault` 增加 `..._settingsStore`，
  使该窗口能读到用户持久化的 `themeMode`。
- **新增守卫测试** `test/theme_subtle_role_test.dart`：断言每个 `*Subtle` 用途的
  底色**不是**同色实底、且底色与文字对比度落在淡底区间（≥4.5），同时断言
  `AppBanner` 四分支的底色与文字对比度达标。防止再有人把 Subtle 角色抹掉。
- **扩展扫描脚本**：`tool/check_no_static_theme_tokens.sh` 增加一条反向规则——
  出现 `context.<name>Text` 或 `context.<name>Solid` **紧邻另一半透明系数**
  （`.withValues(alpha: 0.1` / `.withAlpha(`）时告警，因为这正是本次误映射的签名。

**非目标：**
- 不重做 `unify-accent-tokens-and-fix-light-mode-contrast` 已确立的 token 取值
  （`accentText` 700/300 档、`*Solid` 800 档等）——那批数字由 24 个断言的契约测试看守。
- 不处理 `NotebookLightScope`（浅色笔记本面板）内的 accent 使用——本次已核对其不依赖
  强调色 token。
- 不给无人值守页 header 换图标（`verified_user` / `shield_outlined` 语义仍贴合）。

## Capabilities

### New Capabilities

- `theme-subtle-wash`: 定义"弱强调底"（subtle wash）这一颜色角色的契约——它是半透明
  派生底而非实底，必须与其上的前景文字构成淡底深字的可读组合，且不得与前景同色。

### Modified Capabilities

- `theme-and-brand`: 在「Static accent references are excluded from widget code」之外
  补充一条约束——颜色迁移必须保留原有角色（实底/前景/半透明底三者不可互换），
  并增加一个"半透明底必须与前景异色且达标"的可验证场景。
- `theme-accent-contrast`: 无需求变更。该 capability 定义的是 token 值契约，本次不动
  取值；此处列出仅为说明已核查。

## Impact

**代码 — 修复（误映射 28 处 + banner 4 处 + 窗口 1 处）：**

| 类别 | 处数 | 说明 |
|---|---|---|
| `successSubtle` → 误映射 | 11 | 5 处去 `*Solid`、6 处去 `*Text` |
| `errorSubtle` → 误映射 | 10 | 5 处去 `*Solid`、5 处去 `*Text` |
| `warningSubtle` → 误映射 | 7 | 4 处去 `*Solid`、3 处去 `*Text` |
| `AppBanner` 四分支底色 | 4 | 实底未同步改字色 |
| 密码窗口服务清单 | 1 | 漏 `..._settingsStore` |

`accentSubtle` 的 15 处引用**已正确**迁移到 `context.accentSubtle`，不在修复范围。

涉及文件集中在 `lib/tools/unattended/`、`lib/tools/ops_tool/`、
`lib/tools/private_player/`、`lib/tools/password/`、`lib/shell/`、
`lib/components/app_components.dart`、`lib/main.dart`。

**工具链：**
- `tool/check_no_static_theme_tokens.sh`：新增半透明系数邻近 `*Text`/`*Solid` 的反向告警
- `test/theme_subtle_role_test.dart`：新增
- `.github/workflows/build-release.yml`：`theme-token-guard` job 自动继承新规则，无需改

**不变更：**
- 任何 token 的值
- 深色模式下已正确的实底用途（`*Solid`）与前景用途（`*Text`）
