## Context

参见 `proposal.md - Why`。
本设计旨在将原基于 Tauri 2.x (Rust) + React 19 的「FS-OPS-Tool 磐石运维工具」完整移植并集成到基于 Flutter 3.27 的 V8WorkToolbox 中。

## Goals / Non-Goals

**Goals:**
- 提供完整的独立大窗口运行模式 (`WindowKind.opsTool`)，遵循 V8WorkToolbox Raycast 深色卡片设计规范。
- 采用纯 Dart 生态依赖（`excel`、`mailer`、`cron`），避免任何 Native C/C++ 平台绑定，确保 macOS 打包与分发零阻碍。
- 完整移植 DevOps 流水线能力（GitLab 多项目管理、批量建分支、批量 pom.xml 修改、Jenkins 参数化构建、ArgoCD Image Tag 监控与锁定防漂移）。
- 完整移植运营报告能力（PingCode/Grafana/SQL 数据源、Excel 解析与模板引擎、Markdown 编辑与 HTML 邮件导出、SMTP 邮件发送、Cron 后台调度）。
- 报告中所有需要 AI 的环节（异常指标研判、生成总结摘要、智能问答）直接对接宿主统一的 `AiConfigStore` 与 `AiService`，复用已有配置与密钥。

**Non-Goals:**
- 不重复实现原工具中孤立的「AI 模型配置」与「AI 日志」模块，统一由宿主全局「AI 配置」与系统日志接管。
- 不引入重型浏览器内核爬虫（如 Chromium/Puppeteer），维持原工具轻量、高效的纯 HTTP 会话与 REST API 交互。

## Decisions

### 1. 窗口模式与生命周期架构
- **决策**：使用 `openInNewWindow: true`，在 `desktop_multi_window` 中以 `arguments: 'ops-tool'` 启动 1200x800 独立窗口。
- **原因**：DevOps 批量操作、表格数据呈现、报告编辑及多环境监控属于高信息密度场景，独立窗口体验远优于受限的主启动器小弹窗。
- **服务注入**：在 `lib/main.dart` 的 `WindowKind` 与 `WindowServices.required` 中注册 `WindowKind.opsTool`，保证其子进程依拓扑初始化 `SettingsStore`、`ProxySettings`、`AiConfigStore`。

### 2. 本地持久化设计 (SQLite)
- **决策**：在 `~/Library/Application Support/V8WorkToolbox/ops_tool/ops_tool.db` 中使用 `sqflite` (结合 `sqflite_common_ffi`) 管理本地数据库。
- **表结构**：
  - `ops_connections`: GitLab / Jenkins / ArgoCD 连接配置
  - `ops_selected_projects`: 跨组选择的项目清单
  - `ops_argocd_environments` & `ops_argocd_tags`: 环境与监控 Tag 记录
  - `ops_data_sources` & `ops_sql_queries`: 外部数据源与 SQL 预设
  - `ops_report_templates` & `ops_reports`: 报告模板与历史报告
  - `ops_email_accounts` & `ops_email_recipients`: 发信 SMTP 账户与通讯录
  - `ops_scheduled_tasks` & `ops_task_logs`: 定时任务与调度执行日志
- **替代方案**：曾考虑全 JSON 纯文本文件存储，但因包含大量历史任务日志、SQL 查询和多表关联级联删除，SQLite 事务和查询性能显著更优。

### 3. 核心外部依赖引入
- **决策**：
  - `excel: ^4.0.6`：用于无需 Excel 安装的纯 Dart 本地多工作表解析。
  - `mailer: ^6.1.2`：纯 Dart 实现的 SMTP 发信客户端，支持 TLS、HTML 格式及附件。
  - `cron: ^0.5.1`：用于在应用保活期间驱动定时任务运行。
- **优势**：均为纯 Dart 实现，无平台通道编解码开销，跨平台兼容且构建稳定。

### 4. 全局 AI 服务接入架构
- **决策**：运维工具内部不自建模型连接池，而是直接调用 `AiService.instance.chatStream(...)` 或 `AiService.instance.chat(...)`。
- **交互**：在报告异常告警模块点击「AI 深度研判」时，将告警数据构造成提示词提交给 `AiService`，使用当前宿主处于激活状态的默认文本模型进行研判分析并回写报告。

### 5. UI 架构与组件设计
- **决策**：采用左侧固定导航栏（NavigationRail / Custom Sidebar）+ 右侧多视图切换的布局：
  - `OpsDashboardView`: 关键指标看板与最近报告快速跳转
  - `OpsDevOpsView`: 包含连接配置、项目管理、批量操作、ArgoCD 监控 4 个二级标签
  - `OpsDataSourceView`: PingCode、Grafana、数据库查询配置与结果表格预览
  - `OpsExcelTemplateView`: Excel 拖拽导入与抽取规则模板设计器
  - `OpsReportEditorView`: Markdown 分节编辑、AI 研判与 HTML 预览
  - `OpsSchedulerView`: 定时任务调度器与实时任务日志
  - `OpsEmailView`: SMTP 账户与邮件直发工作台

### 6. ArgoCD 交互模型：可编辑配置表 + 后台常驻巡检（返工决策）
- **背景**：初版实现（tasks 2.3 / 6.3 标记完成时）把该模块降级为「手动点击扫描 → 展示一次性 `TagCheckResult` 快照」。这偏离了原工具的核心模型，导致 `刷新 Tag` / `复制当前到目标` / `保存 Tag 配置` 三个按钮与可编辑列表整块缺失，且 `target_tag` 这一「用户意图」字段无处可写。
- **决策**：以原 `DevOpsPage.tsx` 的 `ArgoCDMonitor` 为唯一交互基准。`argocd_tags` 是**用户维护的配置表**，语义边界必须保持清晰：
  - `current_tag`：只由「刷新 Tag」与后台巡检写入，UI 只读展示。
  - `target_tag`：只由用户编辑（或「复制当前到目标」批量填充），UI 可写。
  - `muted` / `enabled`：逐行开关，决定是否弹窗告警、是否纳入巡检比对。
- **数据流**（取代初版的单向扫描）：
  ```
  刷新 Tag ──▶ listYamlTags() 拉远程 ──▶ 按 project_name merge
                                          (保留 target_tag/muted/enabled)
              ──▶ saveArgoCdTags() 落库 ──▶ 表格重绘
  后台巡检 ──▶ 同 listYamlTags() ──▶ upsert 仅 current_tag/last_checked
              ──▶ 变更时 emit 事件 + 系统通知
  保存配置 ──▶ saveArgoCdTags()（用户编辑后显式落库）
  ```
- **关键约束**：`ArgoCdService` 必须提供 id 稳定合并语义——`id = "${envId}_${projectName}"`，与 `OpsDatabase.updateArgoCdTag` 的 `ConflictAlgorithm.replace` 冲突键对齐，禁止每次扫描生成新 UUID（否则 target_tag 关联全部丢失）。
- **替代方案**：曾考虑维持「只读扫描快照 + 手动触发」的简化交互。放弃原因：`checkAndSyncEnvironment` 已实现锁定回写，需要 `target_tag` 作为比对基准；没有可写配置表，锁定模式在功能上即无法成立。

### 7. 通知通道选型：宿主 OS 原生通知
- **决策**：ArgoCD Tag 变更弹窗走宿主操作系统原生通知（macOS 使用 `osascript display notification`）。
- **原因**：
  - 原版依赖 Tauri 命令动态创建原生通知窗口（`show_notification` 每次 spawn 一个无边框 webview 窗口）。在 Flutter 中复刻需向 `lib/main.dart` 新增一类 `WindowKind` 与窗口生命周期管理，成本与风险不成比例。
  - V8 已有三处成熟先例：`asset_reminder_service.dart`、`scheduled_news_service.dart`、`unattended_service.dart`，均走 `osascript`。沿用既定模式，风格一致且零新依赖。
  - `muted` 的语义（关闭弹窗提醒但仍更新 DB）在 OS 通知通道下映射直接：跳过通知调用即可，不影响 `current_tag` 写回。
- **界内反馈**：通知之外，`ArgoCdService` 暴露一个事件流（`Stream<ArgoCdChangeEvent>`），供 ArgoCD 监控页实时刷新当前行与不一致高亮，替代原版的 `listen('argocd-tag-changed')`。UI 层不再自行轮询。

### 8. 配置仓路径解析与分页（修正原工具既有缺陷）
- **背景**：原版 `parse_projects_path` 要求 `projects_path` 形如 `/tree/master/argocd/projects`（`tree` 段分隔仓库、分支、子目录），仓库名可省略并自动从 GitLab URL 尾段提取。初版移植直接把整个 `projects_path` 当作 URL 编码的项目路径使用，且硬编码 `ref=master`、丢弃子目录——导致带子目录或非 master 分支的环境全部失效。此外原版 `per_page=100` 单页取数，文件数超过 100 时静默截断。
- **决策**：
  - 完整移植 `parse_projects_path` / `extract_repo_from_url` 逻辑，产出 `(repo, branch, file_dir)` 三元组；仓库名为空时回退到 URL 提取。
  - `file_dir` 非空时通过 `path=` 参数限定扫描目录（不再用 `recursive=true` 全仓递归），减少无关文件读取。
  - **分页修正**：`per_page=100` 固定，按 GitLab 标准的 `Link: <url>; rel="next"` 响应头翻页（v3 与 v4 均支持），循环至无 `rel="next"` 为止。相较原版的单页取数，这是本项修正的核心增量；同时避免依赖 `?page=N` 递增试探（v3 部分版本行为不一致）。
  - 项目名推导与原版对齐：取文件名字段的 `values-` 前缀剥离 + 扩展名剥离（如 `values-dc-order.yaml` → `dc-order`），保证 `project_name` 作为合并键跨扫描稳定。

## Risks / Trade-offs

- **[Risk] GitLab 版本碎片化（企业内常驻 GitLab 10.x 旧版本）**
  → **Mitigation**: 移植原 Rust 中的逻辑，在发起 API 请求时先尝试 v4 接口，若返回 404 则平滑回退到 v3 接口。
- **[Risk] 子窗口独立进程导致宿主 AI 配置或网络代理失效**
  → **Mitigation**: 将 `WindowKind.opsTool` 严格纳入 `lib/main.dart` 的 `WindowServices.required` 契约体系，在子窗口入口强制串行等待拓扑初始化完成。
- **[Risk] 定时调度在窗口最小化或隐藏到托盘时的保活**
  → **Mitigation**: 宿主进程本身具备托盘常驻与后台保活机制，调度器由服务层单例持有，不依赖当前是否有打开的前台子窗口。
- **[Risk] 扫描与巡检并发写 `current_tag` 造成配置丢失**
  → 手动「刷新 Tag」与后台巡检都写 `argocd_tags`。若用 `saveArgoCdTags`（delete-then-insert 全量替换）执行巡检，会清掉用户刚编辑但尚未保存的 `target_tag`。
  → **Mitigation**: 巡检一律走 `upsert`（`ConflictAlgorithm.replace` 单行更新，仅触碰 `current_tag`/`target_tag`/`last_checked`）；「刷新 Tag」走 merge-后-全量保存，且保存时以内存中已合并的结果为准，不重新读 DB。
- **[Risk] 后台巡检循环的启动位置与窗口生命周期耦合**
  → 初版 `SchedulerService.instance.start()` 在 `OpsToolMainPage` 内调用，而 ArgoCD 巡检未接入任何调度入口——即便用户已在后台配置好环境与目标 Tag，也永远不会触发比对。
  → **Mitigation**: ArgoCD 巡检循环由 `SchedulerService` 统一持有（与任务调度同一生命周期），按启用环境的最小间隔（`MIN(cron_expr)`，无启用环境时回退 300 秒）自校正下次唤醒时间，环境增删改后无需重启循环。
- **[Risk] 原生通知权限未授权时静默失败**
  → macOS 用户可能在系统设置中拒绝该应用的「通知」权限，`osascript` 返回非零但不影响主流程。
  → **Mitigation**: 通知失败仅记日志不中断巡检；变更本身已通过事件流反映在界面（不一致行高亮），通知仅是第二通道。

## Migration Plan

1. **依赖准备**：在 `pubspec.yaml` 中添加 `excel`、`mailer`、`cron`，执行 `flutter pub get`。
2. **数据与服务层搭建**：
   - 建立 `lib/tools/ops_tool/database/` 数据库引擎与迁移脚本；
   - 建立 `lib/tools/ops_tool/services/`（GitLabClient, JenkinsClient, ArgoCdService, ScraperService, TemplateEngine, EmailService, SchedulerService）。
3. **UI 视图与交互实现**：
   - 建立 `lib/tools/ops_tool/ui/` 及其对应子视图组件。
4. **工具箱注册与窗口连接**：
   - 在 `lib/main.dart` 注册 `WindowKind.opsTool`；
   - 在 `lib/tools/registry.dart` 注册 `OpsToolDefinition`。
5. **功能联调与验收**：验证各模块与 AI 联动。
