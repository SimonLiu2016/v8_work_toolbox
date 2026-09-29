## Context

`refactor-unified-theme-system` 已落地 `AppColors` `ThemeExtension` + `context.<token>` 契约，并把 Shell、设置、对话框、工具页根部接入动态主题（19/19 完成）。本 change 承接该 change §5 划定的剩余范围：**671 处**静态 token 引用，38 个文件，其中 **139 处**位于 `const` 表达式内。

动机见 `proposal.md` — Why，需求契约见 `specs/theme-and-brand/spec.md`。

关键约束：`lib/theme/app_theme.dart` 是唯一允许引用 `AppTheme.<颜色 token>` 的地方（它是 light/dark 两套 preset 的定义源）。其余文件必须走 `BuildContext` 扩展。

```
合法                           非法
─────────────────────────      ─────────────────────────
AppColors.dark = AppColors(     Container(
  bgCard: AppTheme.bgCard,       color: AppTheme.bgCard,   ← 编译期绑定深色
  ...                            ...
)
context.colors.bgCard  ← 好
context.bgCard        ← 好（扩展 getter）
```

## Goals / Non-Goals

**Goals:**
- 671 处引用全部改走动态解析，`flutter analyze` 0 error，深色模式视觉零变化。
- 新增一条 lint 防线，阻止第 672 处出现。
- 按域分批，每批可独立 analyze + 人工验证，任一批次出问题可单独回滚。

**Non-Goals:**
- 不评估 `AppColors(14 token)` → Material 3 `ColorScheme` 的迁移（独立立项）。
- 不新增浅色专属视觉设计、不调 token 值。
- 不重构 widget 结构、不引入新组件、不改业务逻辑。

## Decisions

### 1. 三遍式推进，而非逐文件端到端

- **Decision**：把 38 个文件分成三遍处理 —— 第一遍只做"无 `const` 的纯机械替换"，第二遍专攻 `const` 摘除，第三遍处理 `Scaffold(backgroundColor:)` 与 helper 函数签名。
- **Rationale**：本人在 `refactor-unified-theme-system` 中的实测表明，机械替换后 `flutter analyze` 会一次性报出十几条 `invalid_constant`，逐处定位成本高。按替换类型分批可以让每遍的失败模式单一、可预测，且中途打断也能安全续上。
- **Alternatives Considered**：
  - *逐文件做到干净再下一个*：放弃。单文件的 analyze/编译往返约 4–10 秒，38 个文件意味着 40+ 次往返，且上下文反复切换。
  - *直接上 codemod 脚本全量重写*：放弃。`const` 的摘除依赖 Dart 常量求值语义，正则/rx 脚本在 139 处 const 上误判率不可接受。

### 2. `const` 摘除由 analyze 报错驱动，而非人工预判

- **Decision**：先做完 token 替换，然后跑 `flutter analyze`，拿 `invalid_constant` 的行号精确定位每一处需要摘 `const` 的位置。
- **Rationale**：Dart 编译器是 const 合法性的唯一权威。`const Icon(... color: AppTheme.textTertiary)` 一定非法，但 `const Divider(color: AppTheme.borderSubtle)` 与 `const TextStyle(fontSize: 13, color: AppTheme.textPrimary)` 的容器嵌套深度不一，人工预判容易漏掉外层 `const`。让编译器指出根因最可靠。
- **Alternatives Considered**：逐行 grep `const.*AppTheme\.` 匹配。最初始码里做过这个估算（139 处），但 `refactor-unified-theme-system` 实测中 grep 出的行数与实际报错行数不完全吻合 —— 有些 `const` 行含多个 token 只需要摘一个 `const`，有些深层嵌套的 `const` grep 抓不到。所以 grep 只用于估算，不作为执行依据。

### 3. lint 防线用「扫描脚本 + CI 检查」，不用自定义 lint rule

- **Decision**：新增一个 shell/Python 扫描脚本（`tool/check_no_static_theme_tokens.sh` 或等价），在 CI 与 pre-commit 中运行；**暂不**上 `analysis_options.yaml` 的自定义 lint plugin。
- **Rationale**：Flutter 自定义 lint 需要单独的 analyzer plugin 包与版本配套管理，为一个 30 行规则引入构建依赖不划算。一个 grep/ripgrep 脚本达到同等拦截效果，且规则本身（"排除 `lib/theme/app_theme.dart` 后不得有 `AppTheme.<token>`"）简单到不需要类型信息。
- **Alternatives Considered**：
  - *dart_code_linter / custom_lint 包*：功能更精确（能理解类型与作用域），但需要新增 `pub` 依赖、锁定 analyzer 版本，且团队需维护插件工程。收益/成本不划算。
  - *完全靠 code review*：放弃。671 处的教训正是"没有自动化防线就会长回来"。

### 4. `vocab_book` 并入本 change，不等它所属 change 落地

- **Decision**：`lib/tools/vocab_book/ui/vocab_book_page.dart`（48 处，24 处 const）在本 change 内清理。
- **Rationale**：该目录由 `add-context-menu-lookup-vocab-note` 新建，当前未被 git 跟踪；但该 change 的任务清单经全文检索确认**不含任何样式类任务**，其 spec 也未对 vocab_book 的视觉提出要求。若等它先归档，本 change 会被无限期阻塞在一个无关的依赖上。
- **风险控制**：vocab_book 尚在开发中，清理时可能与它的并行改动冲突。缓解办法是 vocab_book 独立成批、独立 verify，若冲突则由用户裁决是 rebase 还是跳过该批。
- **Alternatives Considered**：等 `add-context-menu-lookup-vocab-note` 完成再动。放弃 —— 那是 44/48 的 change，剩余 4 项全是需真机手测的验证任务，等待时间不可控。

### 5. 深色模式零变化作为硬性验收线

- **Decision**：每一批完成后，除 `flutter analyze` 外，还必须确认该批文件的 git diff 中**不含任何语义性改动**（只有 token 来源的替换与 `const` 摘除）。
- **Rationale**：本次唯一目标是"颜色从编译期常量改为运行时解析"。任何 diff 中出现 widget 结构调整、间距变化、条件逻辑变更，都说明替换越界了，必须回退重做。深色模式的 token 值与浅色一一对应（`AppTheme.bgCard` → `context.bgCard` 在暗色下解析回同一个值），所以只要 diff 干净，深色模式观感必然不变。
- **Alternatives Considered**：截图对比。需要启动 app、切主题、逐个工具页截图，38 个文件的人工比对成本高于 diff 审查。

## Risks / Trade-offs

- **[Risk] `const` 摘除会隐式增加重建开销**：
  `const Icon(...)` 是编译期常量，摘掉 `const` 后每次 build 都新建实例。刚掉了 widget 树 canonicalization 的优化。
  → *Mitigation*：这些是叶子 widget（Icon/Text/Divider/SizedBox/TextStyle），构建成本本身可忽略；`context.<token>` 是一次 `InheritedWidget` 查找，$O(1)$。若后续 profiling 发现问题，再考虑把高频位置的 token 提升到 build 方法顶部缓存。

- **[Risk] 部分文件处于并行开发中，合并冲突**：
  `vocab_book`（未跟踪）、`lookup_panel`（未跟踪）以及 `add-web-search-with-proxy-support` / `optimize-lookup-popover-and-browser-extension` 两个 in-progress change 可能触及同一批文件。
  → *Mitigation*：按域分批 + 每批独立 verify；冲突时优先保留并行业务改动，仅在其上叠加 token 替换。不强行 rebase 他人未完成的工作。

- **[Risk] 某批替换引入视觉回归但 analyze 与 diff 都看不出来**：
  典型如 `AppTheme.textPrimary` 被误替换到不相关的 `colors.textPrimary` 作用域（例如传进了已删除形参的 helper）。
  → *Mitigation*：每批完成后人工过一遍该批 diff；最终交付前由用户在浅色/深色下各扫一遍主要工具页。

- **[Trade-off] 脚本 lint 不如类型感知 lint 精确**：
  正则可能漏报跨行写法。
  → *Mitigation*：规则足够简单（单一前缀匹配 + 单文件白名单），且 `refactor-unified-theme-system` 已验证该 grep 模式能稳定抓出全部 671 处。跨行漏报可通过 CI 的定期人工抽查补充。

## Migration Plan

1. 先加扫描脚本并跑出基线（当前应为 671 处），把脚本接入 CI 但设为 **warning 级**，不阻断构建。
2. 按 `tasks.md` 的分批顺序逐批替换，每批：替换 → `flutter analyze` → diff 自检 → 累计计数应单调下降。
3. 计数归零后，把 CI 检查从 warning 提升为 **error 级**，此时任何新增引用都会阻断。
4. 回滚策略：每批独立 commit，任一批出问题 `git revert` 那一批即可，不影响已完成的批次。

## Open Questions

- 「9 个根级独立工具总入口」（`lib/folder_compare_tool.dart`、`lib/app_shortcut_tool.dart`、`lib/kma_package_tool.dart`、`lib/bc_config_tool.dart`、`lib/bc_config_shell.dart`、`lib/image_resize_tool.dart`、`lib/batch_rename_tool.dart` 等）目前共约 117 处引用。这些工具的维护优先级可能低于 `ops_tool` / `password` 等主力工具。
  → **不影响本 change 的分批与验收标准**（标准是"全部清零"），但实际执行顺序可按使用频率调整。若某批优先级需重排，在执行阶段与用户确认即可，不动 spec 与 tasks 结构。
