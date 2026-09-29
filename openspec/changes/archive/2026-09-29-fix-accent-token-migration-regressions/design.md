## Context

`unify-accent-tokens-and-fix-light-mode-contrast` 批次 F 用一个"按用途分派"的正则把剩余
264 处 `AppTheme.accent*` 批量迁到 `context.*`。规则只识别了两个角色：

```
if 'backgroundColor' in line:  → context.<name>Solid
elif 'color:' in line:          → context.<name>Text
else:                           → context.<name>Solid
```

**漏了第三个角色 `*Subtle`**（12% 半透明底）。43 处 `*Subtle` 引用中，`accentSubtle` 的
15 处因恰好命中 `else` 分支前的显式判断而正确落到 `context.accentSubtle`；其余
`successSubtle` / `warningSubtle` / `errorSubtle` 共 **28 处**被当成普通底色或前景处理：

```
误映射 → *Solid   14 处   (success 5 / error 5 / warning 4)
误映射 → *Text    14 处   (success 6 / error 5 / warning 3)
```

动机见 `proposal.md` — Why；角色契约见 `specs/theme-subtle-wash/spec.md`。

## Goals / Non-Goals

**Goals:**
- 28 处误映射全部恢复为「半透明底 + 深字」。
- `AppBanner` 四分支恢复淡底深字。
- 密码工具窗口读到持久化 themeMode。
- 新增角色守卫（测试 + 扫描规则），让"Subtle 被抹平"这类错误以后进不来。

**Non-Goals:**
- 不改任何 token 的值（父 change 的 24 个契约断言继续看守）。
- 不给无人值守页 header 换图标。
- 不审查 `*Subtle` 之外的迁移正确性——那是父 change 的验收范围。

## Decisions

### 1. 半透明底经 `*Solid.withValues(alpha:)` 派生，不新增 token

- **Decision**：`bg = context.<name>Solid.withValues(alpha: 0x1F / 255)`。
- **Rationale**：父 change 的 design 决策 8 已经定了这条路线（"`*Subtle` 不进
  `AppColors`，经 `context.*` 取值再 `withValues(alpha:)`"），本次只是把没做到的补上。
  实际核对全部 28 处的原 alpha 均为 `0x1F`，故统一系数 `0x1F / 255 ≈ 0.1216`。
- **Alternatives Considered**：
  - *给四个 `*Subtle` 建 token*：会让 `AppColors` 再涨 4 个字段，而它们是纯派生值，
    不需要按主题取不同 alpha。否决。
  - *直接保留 `AppTheme.<name>Subtle` 字面量*：会让扫描规则出现豁免缺口，破坏父 change
    建立的"源码零字面量"不变量。否决。

### 2. `AppBanner` 底色回半透明，文字保持 `textPrimary`

- **Decision**：`bg = context.<name>Solid.withValues(alpha: 0x1F / 255)`，
  文字维持 `context.textPrimary`。
- **Rationale**：banner 文案常为长句（例："首次在 macOS 上操作可能需要授予此工具访问
  Application Support 文件夹的权限…"）。淡底深字在长文本上的可读性优于实底白字，
  且这正是改动前的形态——用户抱怨的正是"深蓝底 + 纯黑字"，回到淡蓝底 + 黑字即可。
- **Alternatives Considered**：保留实底 + 改字为 `context.onAccentSolid`。
  能达标（白字 vs `#1E40AF` = 6.70），但会让四条 banner 变成四个高饱和大色块，
  长文案压在强色底上反而刺眼。否决。

### 3. 密码工具窗口补 `..._settingsStore`，而非给 notifier 改默认值

- **Decision**：`WindowKind.passwordVault` 增加 `..._settingsStore`。
- **Rationale**：根因是该窗口从未 `SettingsStore.instance.init()`，所以
  `themeModeNotifier` 停在 `ThemeMode.system`。修法要让窗口**读到用户偏好**，
  而不是把默认值改成 dark——后者会让所有未 init 的窗口都变暗，是掩盖而非修复。
- **Trade-off**：`passwordVault` 原本只依赖 `_appPaths`，是刻意最轻的窗口。
  补 `_settingsStore` 会增加一次 `app.json` 读取（启动路径上 ~1ms 量级），
  但这是"能读到主题偏好"的必要代价。
- **验证方式**：`WindowServices.requiredNames` 已有测试断言清单覆盖（见
  `test/app_paths_test.dart` 一类的 pattern），补一条"每个 themed 窗口都含
  SettingsStore"的断言，防止再漏。

### 4. 守卫以渲染级断言为主，扫描规则只兜「变量名自证是底色」的情形

- **Decision**：硬守卫放在 `test/theme_subtle_role_test.dart`（25 个断言）；
  扫描规则降级为 warning，判据收窄到
  `(backgroundColor|bg|badgeBg)\s*[:=]` + `Text` + 同行无 `withValues/withAlpha`。
- **Rationale**（实施中三次返工才认清）：
  `color: context.xText` 这一源码形态**同时**用于「wash 底色」与「文字/图标前景」，
  单靠正则无法区分。三次尝试的失败模式：
  1. 抓 `Text|Solid` + 半透明系数 → 把 10 条**正确的 wash 派生**全报出来；
  2. 只抓 `backgroundColor:` → 与实际失效形态（无人值守用裸 `color:`）不符，抓不到；
  3. 扩到裸 `color:` + 无半透明 → 把 5 条**正确的前景用途**也报出来。
- **终版判据为何有效**：`bg =` / `badgeBg =` / `backgroundColor:` 这三个变量名
  **自证是底色位」，误报率可接受；已实测把某处改回 `bg = ...Text` 能触发告警。
- **覆盖盲区（有意接受）**：裸 `color: context.xText` 的 wash 丢失抓不到。
  这类只能由渲染级断言看守——它取的是实际生效色，与源码书写形态无关。
  已在 `tool/check_no_static_theme_tokens.sh` 注释中写明该盲区与分工。

## Risks / Trade-offs

- **[Risk] 28 处分散在多个文件，手工逐处恢复易漏**：
  → *Mitigation*：按"原行含 `<name>Subtle` 的删除行"反推清单（本次已用 `git diff`
  生成完整清单，见 proposal 的 Impact 表），逐处改完用 `git diff` 复核：
  **每一处的新增行必须含 `withValues(alpha: 0x1F / 255)` 或等价写法**。

- **[Risk] 半透明 alpha 统一取 `0x1F` 可能有个别处原本不同**：
  → *Mitigation*：已核对 28 处的原值全部为 `0x1F`。修复时再逐处打印原行确认，
    若发现例外单独处理并记录。

- **[Risk] 深色模式下 wash 的外观会变**：`successSolid` 深色是 300 档还是 800 档？
  父 change 定的是 `*Solid` 深浅统一 800 档，故 `successText.withValues(alpha: 0.12)`
  在深色底上会比原来的 `successSubtle`（基于 500 档 `#22C55E`）更暗一些。
  → *Mitigation*：这正是父 change design 决策 9 记录的有意变化（500 档白字不达标），
  已在父子两个 change 中留痕。**验收时确认深色下 wash 仍可辨**。

## Migration Plan

1. 先写 `test/theme_subtle_role_test.dart` 并让它**失败**（确认守卫有效）。
2. 按 proposal Impact 表逐处修 28 处误映射 + 4 处 banner。
3. 补密码窗口服务清单，并加一条 `requiredNames` 完整性断言。
4. 扫描脚本加反向规则（warning 级）。
5. 全量验证：scan 0 / analyze 0 error / 新测试由红转绿 / 全量 test 不高于基线。
6. 回滚策略：本 change 独立 commit，出问题整体 `git revert`。

## Open Questions

（无。三个根因都已明确定位，修法无取舍空间。）
