## Context

参见 `proposal.md - Why`。

ops_tool 的 UI 层当前全部使用裸 `TextField`，未 import `lib/components/app_components.dart`，因此无法直接复用宿主 `AppTextField` 的 `suffixIcon` 参数。宿主内已有两处成熟的凭据可见性范式，二者形态不同，需要选定其一作为对齐基准：

```
ai_config_page.dart:1442        AppTextField(
                                  obscureText: !keyVisible,
                                  suffixIcon: IconButton(Icon(...), tooltip: ...))

password/item_editor.dart:495   InkWell(Icon(_revealed ? visibility_off : visibility))
                                ↑ 非 TextField，是自绘的「标签 + 掩码文本 + 图标」行
```

凭据的存取链路现状：`ArgoCdService.createGitLabClient()` 直接从 `ArgoCDEnvironment.gitlabPassword` / `gitlabToken` 构造 `GitlabConfig`；`EmailService._buildSmtpServer()` 直接读 `EmailAccount.password`。二者都无「凭据未提供」的显式判定，缺失时表现为 `GitLabClient.login()` 抛「请配置 Personal Access Token」、SMTP 连接失败——错误可归因，但发生在巡检循环内，用户看不到。

## Goals / Non-Goals

**Goals:**
- 用最小的 UI 改动代价，让六个凭据字段具备可发现的显示/隐藏切换，且明文态严格限制在当前弹窗内。
- 让 ArgoCD 环境的管理动作（编辑 / 删除）从「图标猜测」变为「显式入口 + 确认」。
- 把「编辑态凭据留空 = 保持原值」这一语义在 ops_tool 内统一，避免一次无关字段的修改导致凭据被空值覆盖。
- 让「凭据为空却启用」这类不可用配置在保存时就被拒绝，而不是留到巡检时才失败。

**Non-Goals:**
- 不改变凭据的存储形态。`argocd_environments.gitlab_password` / `gitlab_token` 与 `email_accounts.password_encrypted`（列名已存在但 `EmailAccount.toMap()` 实际原样写入明文）继续以明文存于 `ops_tool.db`。接入宿主 `KeychainService` + DEK 需要处理存量数据的解密重加密与「应用未签名时 DEK 不可用」的回退，是独立的架构变更。
- 不从旧工具 `~/Library/Application Support/com.fs-ops-tool.app/fs-ops-tool.db` 迁移任何数据（其 `cron_expr` 为标准 cron 表达式，与迁移版的纯秒数语义不兼容；其 SMTP 密码的加密方案与宿主不同，无法解密复用）。
- 不重构 ops_tool 的整个 UI 基座（不改用 `AppTextField`、不引入统一表单组件、不动其余 20 余处非敏感 `TextField`）。

## Decisions

### 1. 凭据可见性切换：自绘 `suffixIcon` 而非改用 `AppTextField`

- **决策**：在现有裸 `TextField` 上补 `suffixIcon: IconButton(...)`，不引入 `AppTextField`。
- **原因**：`AppTextField` 自带 `label` / `helperText` / `isDense` / `contentPadding` 一整套外观，逐个替换会改变全部 6 个弹窗的视觉密度，且 ops_tool 其他 20 余处字段仍是裸 `TextField`，混用两套基座反而更不一致。`suffixIcon` 是 `InputDecoration` 的原生参数，与 `AppTextField` 的实现等价（`app_components.dart:78` 正是把它透传给 `InputDecoration`）。
- **明文态的作用域**：每个弹窗内的 `StatefulBuilder` 持有各自的 `bool _visible` 局部变量（而非提升到 `State`）。弹窗 `Navigator.pop` 后局部状态自然销毁，天然满足「明文态不跨会话保留」，无需额外的 reset 逻辑。`ops_devops_view.dart` 的环境弹窗与连接弹窗是两个独立的 `showDialog`，各持一份。
- **替代方案**：考虑过在 `_OpsDevOpsViewState` 上放一个全局 `Set<String> _revealedFields`。放弃：跨弹窗持久化明文态违背 spec 要求，且需要在 `dispose` 里清理，收益为零。

### 2. 编辑态凭据不回填：在 UI 层截断，不改模型与 DAO

- **决策**：`_showEnvDialog(env)` 与 `_showEditDialog(conn)` 的 `passCtrl` / `tokenCtrl` 初始值改为空字符串，保存时用「空则保留旧值」的三元表达式写回模型。
- **原因**：`ArgoCDEnvironment` 与 `DevOpsConnection` 的 `toMap()` 是全字段覆盖 + `ConflictAlgorithm.replace`，只要 UI 不传空值，DAO 无需任何改动。把语义放在 UI 层也最贴近用户心智（「我没填就是别动」）。
- **具体形态**：
  ```
  ArgoCD 环境：gitlabPassword: passCtrl.text.trim().isEmpty
                          ? env?.gitlabPassword      // 保留
                          : passCtrl.text.trim(),
  ```
  新建时 `env == null`，`env?.gitlabPassword` 为 null，等价于原逻辑。
- **替代方案**：考虑过在 `OpsDatabase.saveArgoCdEnv` 里做 merge（先 SELECT 再按空值跳过）。放弃：DAO 层的隐式合并会让「保存」语义不透明，且 `toggleScheduledTask` 已有显式 update 的先例，说明本项目倾向显式而非魔法。

### 3. 环境管理入口：详情卡加文字按钮 + chip 图标补 tooltip + 删除确认

- **决策**：三处并行补齐，而非重构 chip。
  - 环境详情卡（`ops_devops_view.dart:1367` 的 `if (env != null)` 块）新增 `OutlinedButton.icon('编辑环境')`，与既有三个 Tag 操作按钮同一行风格，视觉权重对齐。
  - `_envChip` 的铅笔与 ✕ 图标包上 `Tooltip`（`tooltip: '编辑环境'` / `'删除环境'`），保留原位作为快捷入口。
  - `_deleteEnv` 前插入 `showDialog` 确认，文案明示级联影响。
- **原因**：spec 要求「不得以无标签裸图标作为唯一编辑入口」，详情卡文字按钮满足这条；chip tooltip 让老用户保留快捷路径。重构 chip（改为下拉菜单）改动面大且要重排 `Wrap`，非必需。
- **级联提示的准确性**：`argocd_tags.env_id` 是 `FOREIGN KEY ... ON DELETE CASCADE`（`ops_database.dart:187`），但 `PRAGMA foreign_keys = ON` 是在 `onConfigure` 里设置的（`ops_database.dart:31`），sqflite 的连接池下每条连接都会执行，级联确实生效。确认文案可以如实写「同时清除其名下全部 Tag 配置行」。

### 4. 凭据缺失校验：保存时前置拦截，而非巡检时容错

- **决策**：`_showEnvDialog` 的保存回调里，在既有的 `parseProjectsPath` 校验之后追加凭据校验——`passCtrl` 与 `tokenCtrl` 均为空时 `_toast(..., isError: true)` 并 return。
- **原因**：与既有的路径校验同构（同样是在弹窗内 `_toast` 后 return），改动最小且失败点前移到用户眼前。巡检侧的 `checkEnvironment` 已对单环境异常 try/catch 并 `debugPrint`，不需要改。
- **边界**：仅约束「新建/编辑 ArgoCD 环境」这一条路径。DevOps 连接、邮件账户、数据源不加此校验——Jenkins 连接允许匿名访问，数据源的 Grafana 类型用 API Key 而非密码，强校验会误伤。

### 5. 演示环境清理：作为 change 的一次性数据迁移任务

- **决策**：在 tasks.md 中列为一条显式的数据清理任务，通过应用的删除路径或一条 `DELETE` 完成，不在代码里写自动清理逻辑。
- **原因**：演示数据是 `integrate-fs-ops-tool` 落地过程的产物，不是运行时产生的状态。写一段「启动时检测并删除演示环境」的代码会引入永不触发的死分支，且删除用户数据属于不可逆操作，不该由程序静默执行。

## Risks / Trade-offs

- **[Risk] 眼睛按钮让明文凭据可被截屏泄露**
  → 明文态仅存在于当前弹窗内，关闭即恢复脱敏；这与宿主 `ai_config_page` 的既有行为一致，用户对「API Key 可显示」已有预期。真正的风险敞口是凭据以明文存于 SQLite（见 Non-Goals），本 change 不放任也不扩大它。

- **[Risk] 「留空保持原值」让用户误以为已修改密码**
  → 用户在编辑态看不到原凭据内容，若记得「我改过密码」但实际留空了，会以为保存成功而新密码未生效。
  → Mitigation: 弹窗内加 helper 文案「留空则保持原有凭据不变」；保存成功的 toast 不声称凭据已更新。

- **[Risk] 凭据缺失校验拦截了合法的匿名 GitLab 场景**
  → 部分内网 GitLab 允许匿名只读访问配置仓，强校验会挡住这类配置。
  → Mitigation: 校验文案明确指向「访问配置仓」，且仅拦 ArgoCD 环境（该路径必须读 YAML，匿名基本不可行）；若后续确认需要支持匿名，放宽为 warning 而非阻断。

- **[Risk] 删除确认对话框增加一次点击，拖慢批量清理**
  → 用户若配了多个环境需逐个删，每次都要确认。
  → Mitigation: 可接受；删除是不可逆的，且环境数量通常为个位数。

## Migration Plan

1. 清理存量演示环境（`env-sit` / `env-lock` 及其 5 行 Tag），使启用集合为空、巡检循环无失败日志。
2. 按 specs 的三组要求改 UI，`flutter analyze --no-fatal-infos` 保持 0 errors / 0 warnings。
3. 补 widget 测试：凭据字段默认脱敏、点击眼睛后明文、关闭重开恢复脱敏；编辑弹窗不回填已存凭据、留空保存不覆盖。
4. **回滚**：本 change 不涉及数据模型与依赖变更，`git revert` 即可；演示环境数据一旦删除不可恢复（本就是无效配置，无恢复价值）。

## Open Questions

- 邮件账户的「邮箱授权码」当前存于 `password_encrypted` 列（明文）。本次只加眼睛按钮，不动存储。若后续要接 Keychain，需确认 SMTP 授权码是否与密码库的 DEK 共用同一套密钥派生——留待加密 change 决策。
