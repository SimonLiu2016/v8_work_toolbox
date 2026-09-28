## 1. 清理存量演示环境

- [x] 1.1 备份 `~/Library/Application Support/V8WorkToolbox/ops_tool/ops_tool.db`（`cp` 非 rename），确认其中仅含 `env-sit` / `env-lock` 两行演示环境与 5 行 Tag、其余 10 张表为空
- [x] 1.2 删除两行演示环境及其级联 Tag（`DELETE FROM argocd_environments WHERE id IN ('env-sit','env-lock')`），复核 `argocd_environments` 与 `argocd_tags` 均为 0 行
- [x] 1.3 确认删除后启动 ops-tool 窗口无 ArgoCD 巡检失败日志（`loadEnabledArgoCdEnvs` 返回空集时 `_runArgocdCheckOnce` 直接 return）

  > 代码路径核验：`scheduler_service.dart:64-65` 的 `if (envs.isEmpty) return;` 位于任何 `debugPrint` 之前，空集下不产生日志。运行时复检并入 6.6 实机验证（测试环境无 path_provider 实现，`OpsDatabase` 无法在单测中驱动）。

## 2. 凭据字段显示/隐藏切换（specs: 凭据字段默认脱敏且支持临时显示明文）

- [x] 2.1 `ui/ops_devops_view.dart` 连接弹窗：密码字段（L155）与 GitLab PAT 字段（L161）补 `suffixIcon` 眼睛切换；PAT 字段当前未脱敏，改为默认 `obscureText: true`
- [x] 2.2 `ui/ops_devops_view.dart` 环境弹窗：GitLab 密码（L1142）与 Personal Access Token（L1148）补眼睛切换
- [x] 2.3 `ui/ops_email_view.dart`：邮箱授权码字段（L100）补眼睛切换
- [x] 2.4 `ui/ops_datasource_view.dart`：数据源密码字段（L95）补眼睛切换；Grafana 分支的 `keyCtrl`（API Key / Token）当前未脱敏，补脱敏 + 眼睛切换
- [x] 2.5 每个弹窗的可见性状态用 `StatefulBuilder` 局部 `bool` 持有（design D1），不提升到 `State`，确保 `Navigator.pop` 后明文态随之销毁
- [x] 2.6 图标与 tooltip 对齐 `ai_config_page.dart:1452` 范式：`keyVisible ? Icons.visibility : Icons.visibility_off`，tooltip 为「显示/隐藏」

## 3. 编辑态凭据留空保持原值（specs: 编辑既有凭据时留空表示保持原值）

- [x] 3.1 `_showEnvDialog(env)`：`passCtrl` / `tokenCtrl` 初始值改为空字符串，不再用 `env?.gitlabPassword ?? ''` 回填
- [x] 3.2 `_showEnvDialog` 保存处（L1222-1223）改为三元：空则沿用 `env?.gitlabPassword` / `env?.gitlabToken`，非空则写新值；`env == null` 时行为不变
- [x] 3.3 `_showEditDialog(conn)`：`passCtrl` / `tokenCtrl` 初始值同样改为空串，保存处保留 `config` 中原值（注意 `token` 为「非空才写入」的既有语义，勿把空 token 写进 map）
- [x] 3.4 两个弹窗的凭据字段补 helper 文案「留空则保持原有凭据不变」；保存成功 toast 不断言凭据已更新
- [x] 3.5 `_toggleEnv`（L1263）已显式传递 `env.gitlabPassword` / `env.gitlabToken`，复核启用开关切换不会因本改动丢凭据

## 4. ArgoCD 环境管理入口（specs: 管理入口可发现且破坏性操作需确认）

- [x] 4.1 环境详情卡（L1367 起的 `if (env != null)` 块）新增「编辑环境」`OutlinedButton.icon`，点击调 `_showEnvDialog(env)`
- [x] 4.2 `_envChip` 的铅笔图标与 ✕ 图标包 `Tooltip`（「编辑环境」/「删除环境」）
- [x] 4.3 `_deleteEnv` 前插入确认对话框，文案明示「将同时清除该环境名下全部 Tag 配置行」，仅确认后执行删除

## 5. 凭据缺失前置校验（specs: 凭据为空的环境不允许启用）

- [x] 5.1 `_showEnvDialog` 保存回调在既有 `parseProjectsPath` 校验之后追加：密码与 Token 均为空时 `_toast` 报错并 return
- [x] 5.2 确认该校验只作用于 ArgoCD 环境路径，不改 DevOps 连接 / 邮件账户 / 数据源的保存逻辑（design D4）

## 6. 验证

- [x] 6.1 运行 `flutter analyze --no-fatal-infos`，确认 0 errors、0 warnings（ops_tool 相关 0 条）
- [x] 6.2 新增 widget 测试：凭据字段默认脱敏 → 点眼睛变明文 → 关闭弹窗重开恢复脱敏（覆盖环境弹窗与邮件弹窗两处）
- [x] 6.3 新增测试：以非空 `gitlabPassword` / `gitlabToken` 构造 `ArgoCDEnvironment`，走保存路径且凭据输入框为空，断言库中凭据未被覆盖
- [x] 6.4 新增测试：凭据全空的环境保存被拒绝（断言 toast/返回值路径），并断言其不出现在 `loadEnabledArgoCdEnvs` 结果中
- [x] 6.5 运行 `flutter test`，确认无新增失败（既有 13 处环境依赖型失败清单保持不变）

  > 实测 690 通过 / 1 跳过 / 14 失败。ops_tool 相关 0 失败；13 处与基线完全一致（`notebook_editor_test` ×3、`notebook_table_interactive_test` ×2、`table_*` 五个文件各 1、`pointer_tap_table_test`、`notebook_codeblock_interactive_test`、`disk_slimmer_hardening_verify_test` ×2、`evernote_space_routing_test`）。第 14 处是 `evernote_import_test.dart` 的 `detectLocalEvernote` 超时——同一文件内下一行的 `const notesPath = '/Users/simon/Desktop/我的笔记.notes'` 硬编码本机路径且该文件不存在，与 `v8worktoolbox-notes.md` 记忆里「环境依赖型失败」同一类，与本 change 无关。
- [ ] 6.6 实机验证：新建 ArgoCD 环境（内网 GitLab + PAT）→ 编辑该环境确认弹窗不回填密码 → 刷新 Tag 能拉到远端项目列表

  > 构建部署已于 2026-09-22 09:14 完成（clean → release build → codesign --strict 通过 → AOT 快照哈希 2d4b548e… 安装前后一致 → /Applications 替换，旧版备份为 .bak-20260922）。启动采样 stderr 仅见 notebook.db 的既有 `duplicate column name` 迁移告警（与 ops_tool 无关），无未捕获异常。
  > 剩余待用户操作：打开「磐石运维工具」→ DevOps 流水线 → ArgoCD 监控 → 新建环境（填内网 GitLab + PAT）→ 点详情卡「编辑环境」确认密码框为空 → 点「刷新 Tag」确认能拉到远端 values-*.yaml 列表。
