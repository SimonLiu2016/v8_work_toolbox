## Context

参见 `proposal.md - Why`。

已用真实 Personal Access Token 对配置仓做过 API 层验证，结论明确：

```
项目      repository/config-fs-argocd-sit   (project id = 60, 默认分支 master)
GET /repository/tree?path=argocd%2Fprojects&ref=master&per_page=100
  → 100 条，Link: rel="next" 指向 page=2
GET /repository/tree?...&page=2
  → 20 条，无 next
合计    120 条 = values-*.yaml ×117 + templates(目录) ×1 + Chart.yaml ×1 + demo.yaml ×1
        （不含 .gitlab-ci.yml）

GET /repository/files/argocd%2Fprojects%2Fvalues-adpt-b2b-order.yaml/raw?ref=master
  → HTTP 200
      Image:
        ImagePullPolicy: Always
        Project: fs
        Repository: ctf-acr-registry-vpc.cn-shenzhen.cr.aliyuncs.com
        Tag: 1.6.24.0-54f4f991
```

即：`readFile` 路径编码正确、`Link` 头解析逻辑（`linkNextUrl`）在此真实 header 上能正确解出 next URL、`extractImageTag` 对该文件能取出正确 Tag。故障集中在「tree 列举」这一跳。

数据路径分裂的实测证据：

```
~/Library/Application Support/V8WorkToolbox/             ← 旧（历史数据所在）
    .dek / .secrets.bin / ai_config.json / app.json /
    PrivateMedia/ / config/ / logs/ / ops_tool/ops_tool.db

~/Library/Application Support/com.v8en.V8WorkToolbox/    ← 新（沙盒重定向目标）
    notebook_attachments/ (423M, 757 项) / ops_tool/ops_tool.db
    （无 ai_config.json、无 .dek、无 PrivateMedia）

~/Documents/notebook.db (44.6M)                          ← 两版共用，未受影响
```

`codesign -d --entitlements` 显示新 app 带 `com.apple.security.files.user-selected.read-write` 等四项文件授权；`ENABLE_APP_SANDBOX` 未显式设置，`CODE_SIGN_STYLE` 为 `Automatic`。entitlement 的存在使 `path_provider` 走容器化路径。

## Goals / Non-Goals

**Goals:**
- 让「刷新 Tag」对真实的 117 个 `values-*.yaml` 完整列举，且非服务文件不出现在列表。
- 让列举失败可见，不再以「只刷出一个空 Tag」的形式呈现。
- 关闭沙盒，使 `getApplicationSupportDirectory()` 回到 `~/Library/Application Support/V8WorkToolbox/`，历史配置与密钥重新可见。
- 消除 ArgoCD 环境编辑入口的重复。

**Non-Goals:**
- 不重构 GitLab 客户端的认证与 v3/v4 回退机制。
- 不改造笔记附件的寻址方式（423M / 757 项仍在 `com.v8en.V8WorkToolbox` 路径下）；本 change 只保证附件仍可被读取（见 Risks 第 3 条）。
- 不引入 YAML 解析库；`extractImageTag` 继续用行扫描，只补引号剥离。
- 不做凭据加密（明文 SQLite 的问题仍在，属独立议题）。

## Decisions

### 1. 去沙盒：删四项文件授权，而非删全部 entitlement

- **决策**：从 `DebugProfile.entitlements` 与 `Release.entitlements` 中移除 `files.user-selected.read-write`、`files.downloads.read-write`、`files.desktop.read-write`、`files.documents.read-write`；保留 `network.client`、`network.server`、`automation.apple-events`、`cs.allow-unsigned-executable-memory`。
- **原因**：本工具的功能面决定它不该被沙盒约束——ArgoCD 巡检要读内网 GitLab、SMTP 发信、`osascript` 系统通知（`ops_notifier.dart` 走 `Process.run('osascript')`），而沙盒并不会为这些带来额外安全性；同时 `reader_config_store`、`vault_store`、`kek_manager`、`private_storage_manager`、`settings_store`、`note_store`、`ops_database` 等 12 个模块全部依赖 `getApplicationSupportDirectory()`，路径漂移会让它们的存量数据一次性失联。
- **为什么不是删光 entitlement**：`network.client` 是访问 GitLab/Jenkins/SMTP 的必要条件；`automation.apple-events` 是 `osascript` 通知的必要条件；`cs.allow-unsigned-executable-memory` 与 Flutter 引擎相关。这三项去掉会直接破坏功能。
- **替代方案**：保留沙盒，改为在启动时把数据从新路径迁回旧路径。放弃：每次重新部署都会再次分裂，用户需反复迁移；且沙盒化还会让 `window_manager`、`desktop_multi_window` 等既有窗口能力的行为发生变化（Risks 第 2 条）。

### 2. tree 列举：显式构造查询参数，并对失败显式报错

- **决策**：`listRepositoryFiles` 首屏 URL 由 `Uri(queryParameters: {...})` 显式生成，`path` 为空时**不带** `path` 参数（而非带空值——GitLab 对 `path=` 空值会返回根目录，这正是本次故障最可能的触发点）；对非 2xx 响应、JSON 非数组、条目缺少 `name`/`path` 三种情形分别抛出可归因异常。
- **原因**：现有代码已用 `Uri(queryParameters:)`，问题在于 `path` 为空串时 `if (path.isNotEmpty)` 分支不写入参数——这条本身是对的。因此真实触发点更可能是请求构造之外的因素（例如 GitLab 对含 `%2F` 的 `path` 在某些版本上的解析差异）。无论根因为何，**「退化成根目录列举」必须被发现**，所以本次同时加上「列举结果数量为 0 或首屏不含任何目标前缀文件时视为异常」的判据，使故障不再静默。
- **兜底校验**：`listYamlTags` 在拿到文件列表后，若 `values-` 前缀文件数为 0 而目录下确实返回了条目，SHALL 抛出带目录路径与分支名的异常，由巡检/UI 呈现。
- **替代方案**：改用 `recursive=true` 全仓遍历后本地过滤。放弃：117 个文件分布在平铺一层，`recursive` 会把 `templates/` 子目录乃至整个仓的 Helm 模板都拉进来，请求量与误报都增加。

### 3. 服务文件过滤：`values-` 前缀 + 排除目录

- **决策**：`listYamlTags` 的入口条件由「扩展名为 `.yaml`/`.yml`」改为「文件名以 `values-` 开头且以 `.yaml` 或 `.yml` 结尾」，并跳过 `type == 'tree'` 的条目。
- **原因**：`argocd/projects` 下实测有 `Chart.yaml`、`demo.yaml`、`templates/`，这些都不是微服务。`values-` 前缀是本项目配置仓的命名约定（用户确认：`values-adpt-b2b-order.yaml` → `adpt-b2b-order`）。
- **注意**：`RepoFile` 已有 `type` 字段但此前从未被使用（全仓 grep 无引用），本次启用。

### 4. 失败反馈：逐文件收集，汇总到 UI

- **决策**：`listYamlTags` 返回结果从 `List<ArgoCdYamlTag>` 改为包含成功列表与失败列表的结构；`refreshEnvTags` 将其带到 UI，toast 文案变为「已刷新 N 个 Tag，M 个文件读取失败」。
- **原因**：`catch (_) {}` 是本次故障难以定位的直接原因。117 个文件全部失败与全部成功在旧实现下对外表现几乎无差别。
- **替代方案**：只 `debugPrint`。放弃：用户在 release 包里看不到 stderr，等于没反馈。

### 5. Tag 值引号剥离

- **决策**：`extractImageTag` 返回值若以 `"` 或 `'` 开头结尾且长度 ≥ 2，剥离首尾一对。
- **原因**：Helm values 中 `tag: "1.6.24.0"` 常见；不剥则比对时 `"1.6.24.0" != 1.6.24.0`，所有行都会被误判为不一致并触发锁定回写（写入带引号的值，虽语义等价但产生无意义 commit）。

### 6. 编辑入口收敛：删 chip 铅笔，留详情卡按钮

- **决策**：移除 `_envChip` 中的铅笔 `InkWell`（触发 `_showEnvDialog(env)`），保留 chip 的环境名点击（选中）、Switch（启停）、✕（删除）；编辑只走详情卡的「编辑环境」文字按钮。
- **原因**：两处入口功能完全相同，属上一个 change 为满足「编辑入口可发现」而叠加产生的冗余。spec 已改为「编辑入口唯一」。

## Risks / Trade-offs

- **[Risk] 去沙盒后 app 需要重新签名，用户系统可能仍缓存旧授权状态**
  → Mitigation: 走 `flutter clean` → `build macos --release` → `codesign -v --strict` → 暂存 `/tmp/deploy` → 备份旧版 → 替换 → 校验 AOT 快照哈希；并提示用户在替换后首次启动若弹出授权框需重新同意。

- **[Risk] 笔记附件仍留在 `com.v8en.V8WorkToolbox/notebook_attachments`（423M / 757 项），去沙盒后 `note_store.dart:29` 会改用旧路径创建新的空附件目录，导致历史附件的图片全部显示为裂图**
  → Mitigation: 本 change 的数据归位步骤包含把 `notebook_attachments` 整体迁到旧路径（`mv`，同卷移动为瞬时），并在迁移后抽样比对文件数与总字节数一致。若用户不希望移动，备选方案是在 `note_store.dart` 的附件目录解析中增加「旧路径不存在而新路径存在时回退」的一次性兼容。

- **[Risk] 沙盒版 `ops_tool.db`（含新建的 SIT 环境）与旧库都有数据，直接覆盖会丢其一**
  → Mitigation: 旧库仅剩演示环境残片（Tag 5 行、环境 0 行），新库只有 1 个 SIT 环境 + 1 行 `.gitlab-ci` 垃圾数据。归位策略是：以新库的 SIT 环境为准写入旧库，`.gitlab-ci` 那行随环境重建自然消失；归位前把两个库都另行 `cp` 备份。

- **[Risk] `listRepositoryFiles` 的真实故障点未经运行时日志确认，「显式构造参数」可能并未解决问题**
  → Mitigation: 按 D2 增加兜底校验（目标前缀文件数为 0 即抛异常），使故障至少可见；同时在 tasks 中安排一次带 PAT 的联调验证（直接用同一 curl 序列比对两端文件数是否都是 117），若仍不符再补日志定位。

- **[Risk] `values-` 前缀是约定而非强制，配置仓若引入非 `values-` 命名的服务文件会被静默排除**
  → Mitigation: 在 UI 的成功/失败计数之外，补充展示「已跳过 N 个非 values-*.yaml 条目」，使用户能察觉命名约定被破坏。

## Migration Plan

1. 备份两个 `ops_tool.db` 与 `notebook_attachments` 目录清单。
2. 改 entitlement（删 4 项文件授权）。
3. 改 `gitlab_client.dart`（列举参数与错误）、`argocd_service.dart`（过滤、Type 跳过、失败汇总、引号剥离）、`ops_devops_view.dart`（删 chip 铅笔、toast 含失败数）。
4. 补/改单测：`values-` 过滤（含 `Chart.yaml` / `demo.yaml` / 目录条目 / `.gitlab-ci.yml` 反例）、引号剥离、分页翻页。
5. `flutter analyze` 保持 0 errors / 0 warnings；`flutter test` 确认无新增失败。
6. `flutter clean` → `build macos --release` → `codesign -v --strict` → 暂存 → 备份 → 替换 → 校验 AOT 哈希。
7. 启动后数据归位：把 `com.v8en.V8WorkToolbox/notebook_attachments` 迁回旧路径，把 SIT 环境写入旧库，抽样核对。
8. 联调验证：新建/选中 SIT 环境点「刷新 Tag」，确认列表为 117 行、每行 `current_tag` 非空（除确实无 tag 的文件）、无 `Chart.yaml` / `.gitlab-ci` 行。
9. **回滚**：`/Applications/V8WorkToolbox.app.bak-20260922` 为沙盒版完整备份；数据侧两个 `ops_tool.db` 与 `notebook_attachments` 均已步骤 1 备份，可原样还原。

## Open Questions

- `listRepositoryFiles` 失真的运行时根因（是 `path` 参数丢失、GitLab 版本对 `%2F` 的解析差异，还是别的）尚未经日志确认。已用 D2 的兜底校验与 tasks 中的联调验证覆盖；若联调仍不符，需要临时加日志再构建一轮。此项不影响 spec 与任务清单，可延后。
