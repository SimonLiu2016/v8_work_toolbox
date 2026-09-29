## 1. 守卫先行（先红）

> 顺序：守卫必须先存在且**当前是红的**，否则无法证明它真能抓住本类错误。
> 若写完就是绿的，说明断言写得太松或没覆盖到实际形态。

- [x] 1.1 新建 `test/theme_subtle_role_test.dart`，内置 WCAG 对比度计算
- [x] 1.2 断言「wash 底色 ≠ 同名前景」：对每处 wash 用途，取底色与文字色，二者必须相异
- [x] 1.3 断言「wash 底 + 文字色对比度 ≥ 4.5」：两种模式各一遍
- [x] 1.4 断言 `AppBanner` 四分支（info/success/warning/error）的底色与 body 文字对比度 ≥ 4.5
- [x] 1.5 断言每个 `WindowKind` 的服务清单：凡渲染 themed `MaterialApp` 的窗口都含 `SettingsStore`
- [x] 1.6 跑一遍确认这些断言**当前失败**（记录失败清单，作为修复的对照基线）

## 2. 修复 28 处 wash 误映射

> 清单由 `git diff` 反推：凡删除行含 `AppTheme.<name>Subtle` 且新增行落到
> `context.<name>Solid` / `context.<name>Text` 的位置。
> **验收标准**：每处修复后，该行新增部分必须含 `withValues(alpha: 0x1F / 255)`
> （已核对 28 处原 alpha 全为 `0x1F`）。

- [x] 2.1 `successSubtle` 11 处 → `context.successText.withValues(alpha: 0x1F / 255)`
- [x] 2.2 `errorSubtle` 10 处 → `context.errorText.withValues(alpha: 0x1F / 255)`
- [x] 2.3 `warningSubtle` 7 处 → `context.warningText.withValues(alpha: 0x1F / 255)`
- [x] 2.4 逐处 `git diff` 复核：新增行含半透明派生写法，且同处的前景色为 `context.<name>Text`
- [x] 2.5 确认 `accentSubtle` 的 15 处未被误伤（它们本已正确落到 `context.accentSubtle`）

## 3. 修复 AppBanner 与无人值守 header

- [x] 3.1 `lib/components/app_components.dart` 的 `AppBanner` 四分支：`bg` 从
      `context.<name>Solid` 改为 `context.<name>Text.withValues(alpha: 0x1F / 255)`，
      body 文字维持 `context.textPrimary`
- [x] 3.2 `lib/tools/unattended/unattended_page.dart` 左上角图标容器：底色从
      `context.successText` / `context.accentSubtle` 改为
      `context.successText.withValues(alpha: 0x1F / 255)` / `context.accentSubtle`，
      图标色保持 `context.<name>Text`
- [x] 3.3 同文件的图标底座边框（`withAlpha(80)` 那类）核对是否也需同步调整

## 4. 修复密码工具窗口主题

- [x] 4.1 `lib/main.dart` 的 `WindowKind.passwordVault` 增加 `..._settingsStore`
- [x] 4.2 加一条断言：凡渲染 themed `MaterialApp` 的 `WindowKind` 其 `requiredNames` 都含 `SettingsStore`
- [x] 4.3 人工确认密码窗口启动路径没有因多读一次 `app.json` 出现可见延迟

## 5. 扫描脚本反向规则

- [x] 5.1 `tool/check_no_static_theme_tokens.sh` 新增：`context.<name>Text` 或
      `context.<name>Solid` 同句内伴随 `.withValues(alpha: 0.1` / `.withAlpha(` 时输出
      warning 级告警（可能是把 text 值当 wash 用的误映射签名）
- [x] 5.2 在脚本头部注释说明该规则针对的失效模式，并标注为 warning 级的理由
      （合法用途如禁用态 `Solid.withValues(alpha: 0.35)` 会被误报，需人工判断）

## 6. 验证与部署

- [x] 6.1 扫描脚本：`AppTheme.<token>` 计数仍为 **0**；新反向规则只产生可解释的告警
- [x] 6.2 1.6 记录的失败清单全部转绿
- [x] 6.3 `flutter analyze` 0 error，issue 总数不高于 216
- [x] 6.4 `flutter test` 全量，失败数不高于父 change 的基线（`+761 ~1 -14`）
- [x] 6.5 `git diff` 自检：本 change 的 diff 仅含 wash 派生、banner 底色、窗口服务清单三类改动
- [x] 6.6 `flutter build macos --release` 通过
- [x] 6.7 执行 `./scripts/deploy_local.sh` 部署
- [x] 6.8 人工验收（浅色 + 深色）：无人值守左上角图标容器、全局客户端 Hook 接入列表状态条、
      白名单状态条、实时审批审计流水状态、BC 配置与应用快捷键的提示条、密码工具独立窗口主题

## 实施记录

### §1 守卫先行：确认 8 处红（修复对照基线）

`test/theme_subtle_role_test.dart` 建好后跑出 **8 失败**，与预期完全吻合：

```
AppBanner 四分支 light: info    / success / warning / error     ← 4 处
AppBanner 四分支 dark:  success / warning / error               ← 3 处
                                 · dark:info 侥幸通过（深底下深蓝实底+浅字恰好可读）
窗口服务清单完整性（passwordVault 缺 SettingsStore）            ← 1 处
```

实测对比度（light 模式）：

```
info    banner 底 #1E40AF + 正文 #0F172A  = 2.05
success banner 底 #166534 + 正文 #0F172A  = 2.50
warning banner 底 #854D0E + 正文 #0F172A  = 2.61
error   banner 底 #991B1B + 正文 #0F172A  = 2.15
```

` wash 角色契约`（wash ≠ 前景 / wash+前景 ≥4.5）两组断言**全绿**——因为它们校验的是
「若按正确写法派生会怎样」，说明契约本身可满足，红的是当前实现。

### §2 28 处误映射：用 difflib 精确定位

`git diff` 的 hunk 配对法一度只找出 4 处（`/tmp/all.diff` 是 L3 中途生成的旧快照）。
改用 **HEAD 版与当前版逐行 difflib 对齐**后拿到完整 28 处：

```
success 11 / error 10 / warning 7
按类型：Text 17、Solid 11
按文件：unattended 6、ai_log_dialog 4、app_components 3、ops_devops 3……
```

统一改为 `context.<name>Text.withValues(alpha: 0x1F / 255)`——原 alpha 已逐处核对全为 `0x1F`。

### §5 扫描规则的两次返工（重要教训）

1. **第一版方向搞反**：抓 `Text|Solid` + `withValues/withAlpha`。
   结果把 10 条**正确的 wash 派生**全报出来——`Text.withValues(alpha: 0.12)`
   恰恰是修复后的正确形态。
2. **第二版只抓 `backgroundColor:`**：与实际失效形态（无人值守用的是裸
   `color:`）不符，抓不到。
3. **第三版扩到裸 `color:` + 无半透明**：把 5 条**正确的前途用途**（文字/图标色）
   也报出来。最终认清：`color: context.xText` 这一形态**无法与"文字前景"区分**，
   单靠正则做不到。

终版判据：`(backgroundColor|bg|badgeBg) *=` + `Text` + 同行无 `withValues/withAlpha`。
已实测：把某处改回 `bg = ...Text` 能触发告警。

**覆盖盲区（有意接受）**：裸 `color: context.xText` 的 wash 丢失抓不到。
真正的守卫是 `test/theme_subtle_role_test.dart` 的渲染级断言（25 个断言全绿）——
它能取到实际生效的底色与文字色，不受源码书写形态影响。已在脚本注释中写明。

### §6 验证结果（截至部署）

```
扫描脚本          AppTheme.<token> 仍 0；反向 wash 规则 0 告警
守卫测试          theme_subtle_role_test.dart 25 断言全绿
                  （§1 记录的红基线 8 项全部转绿）
analyze           0 error，218 issues（基线 216）
flutter test      +677 ~1 -12；相对父 change 基线**零新增失败**
release build     164.6MB（首次 INTERRUPTED 为 Xcode 瞬时问题，重跑成功）
deploy_local.sh   AOT 81d867a9 → 1909aa98
```

**待人工验收（6.8）**：浅色 + 深色下目视六个问题的对应位置。

### 人工验收结论（用户已确认通过）

六个问题（无人值守绿色方块、Hook 接入状态条、白名单状态条、审计流水状态、
BC 配置/应用快捷键提示区、密码工具独立窗口主题）已由用户目视验证通过。

（记录完毕）
