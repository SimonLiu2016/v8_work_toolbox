## 1. 依赖与基础脚手架

- [x] 1.1 在 `pubspec.yaml` 中添加 `mailer: ^6.1.2`、`cron: ^0.5.1`、`sqflite: ^2.4.1`（Excel 沿用已有 archive/xml 方案），并运行 `flutter pub get`
- [x] 1.2 创建 `lib/tools/ops_tool` 基础模块与子目录（models, database, services, ui）
- [x] 1.3 建立本地 SQLite 数据库操作层 `OpsDatabase`，实现 12 张核心表的初始化与版本迁移机制

## 2. DevOps 流水线客户端与服务层

- [x] 2.1 实现 `GitLabClient`（支持 v3/v4 自动回退、Group 项目检索、多分支批量创建、`pom.xml` 正则解析与版本提交）
- [x] 2.2 实现 `JenkinsClient`（CSRF Crumb 获取、参数化构建触发、构建状态异步轮询）
- [x] 2.3 实现 `ArgoCdService`（配置仓 YAML 镜像 Tag 提取、差异比对、监控告警模式与锁定修复 Commit 回写；返工补全可编辑配置表与巡检写回语义，见 9.2）

## 3. 运营数据源与报告渲染引擎

- [x] 3.1 实现 `ScraperClient`（PingCode 登录会话与工作项查询、Grafana 看板/数据源代理、PhpMyAdmin/SQL 查询执行）
- [x] 3.2 实现 `ExcelService`（基于纯 Dart `excel` 库解析多 Sheet 数据与单元格数据结构）
- [x] 3.3 实现 `TemplateEngine`（单元格坐标解析、列统计聚合 sum/count/avg/max/min、DB SQL 动态填充与占位符替换）
- [x] 3.4 实现 `ReportGenerator`（Markdown 多分节组合、带内联样式的 HTML 邮件排版渲染）

## 4. 定时调度与邮件服务

- [x] 4.1 实现 `EmailService`（基于 `mailer` 库的 SMTP 连接测试、TLS 认证与 HTML 邮件投递）
- [x] 4.2 实现 `SchedulerService`（基于 `cron` 库的后台调度执行循环、任务启停切换与任务日志持久化）

## 5. 宿主 AI 能力对接

- [x] 5.1 封装 `OpsAiHelper`，直连宿主 `AiService.instance`，实现报告异常指标智能研判、摘要总结与问答

## 6. UI 界面与交互实现

- [x] 6.1 实现 `OpsToolMainPage`（左侧深色卡片导航栏、状态保活与右侧内容工作区路由）
- [x] 6.2 实现 仪表盘视图 `OpsDashboardView`（关键运维与报告指标卡片、最近报告列表及快速入口）
- [x] 6.3 实现 DevOps 控制台 `OpsDevOpsView`（连接配置、项目多选过滤、批量创建分支/更新 pom、ArgoCD 监控；返工对齐原交互，见 9.5）
- [x] 6.4 实现 数据源视图 `OpsDataSourceView`（PingCode / Grafana / SQL 查询管理、数据测试与表格预览）
- [x] 6.5 实现 Excel 与模板设计器 `OpsExcelTemplateView`（文件拖拽导入、抽取规则配置、模板实时生成）
- [x] 6.6 实现 报告中心视图 `OpsReportEditorView`（Markdown 分节编辑、AI 研判交互、HTML 导出与快速转邮件）
- [x] 6.7 实现 定时调度视图 `OpsSchedulerView`（Cron 表达式可视化预设、任务开关、手动触发与执行日志弹窗）
- [x] 6.8 实现 邮件管理视图 `OpsEmailView`（SMTP 账户管理、通讯录分组配置、邮件直发）

## 7. 窗口生命周期与工具箱注册

- [x] 7.1 在 `lib/main.dart` 声明 `WindowKind.opsTool` 并将其纳入 `WindowServices.required` 必需服务清单
- [x] 7.2 在 `lib/tools/registry.dart` 注册 `OpsToolDefinition`（配置 `openInNewWindow: true` 独立窗口唤起）

## 8. 验证与测试

- [x] 8.1 运行 `flutter analyze --no-fatal-infos` 保证项目 0 errors, 0 warnings
- [x] 8.2 编写并执行单元测试，验证模板引擎公式计算、数据库迁移及核心客户端逻辑

## 9. ArgoCD 监控返工（交互模型对齐原工具 + 分页修正）

> 背景：2.3 与 6.3 初版实现将 ArgoCD 模块降级为「手动扫描 → 一次性结果快照」，偏离原工具「可编辑配置表 + 后台常驻巡检 + 通知告警」的交互模型，导致 `刷新 Tag` / `复制当前到目标` / `保存 Tag 配置` 及可编辑列表整块缺失。详见 `design.md` 决策 6~8。本节完成后回勾 2.3 与 6.3。

### 9.1 路径解析与分页（`services/argocd_service.dart`）

- [x] 9.1.1 移植 `parse_projects_path`：解析 `/tree/<branch>/<dir...>` 结构产出 `(repo, branch, fileDir)`，仓库名为空时按 `extract_repo_from_url` 从 GitLab URL 尾段回退提取
- [x] 9.1.2 `listYamlTags` 改用解析结果：以 `project_id` 查询项目、`path=` 限定子目录、使用解析出的 `branch`（替换硬编码 `ref=master` 与全仓 `recursive=true`）
- [x] 9.1.3 **分页修正**：按 GitLab `Link: <url>; rel="next"` 响应头循环翻页（`per_page=100` 固定），直至无 `rel="next"`；v3/v4 均适用
- [x] 9.1.4 项目名推导与原版对齐：文件名剥离 `values-` 前缀与 `.yaml`/`.yml` 扩展名（如 `values-dc-order.yaml` → `dc-order`）
- [x] 9.1.5 单元测试：`Link: rel="next"` 响应头解析（含无 next 的末页与空头）、`values-` 前缀剥离、含子目录与非 master 分支的路径解析、仓库名 URL 回退

  > 注：跨页遍历的端到端完整性需要 mock `GitLabClient` 响应，当前仅覆盖单页解析与翻页判定逻辑。

### 9.2 配置表合并与巡检写回语义

- [x] 9.2.1 新增 `refreshEnvTags(env)`：拉取远程后按 `projectName` 合并，保留既有 `targetTag` / `muted` / `enabled`，稳定生成 `id = "${envId}_${projectName}"`（对齐 `updateArgoCdTag` 的 replace 冲突键），经 `saveArgoCdTags` 全量落库并返回结果
- [x] 9.2.2 新增 `upsertArgoCdTags(envId, entries)`：单行 `ConflictAlgorithm.replace` 写回 `currentTag` / `lastChecked`，供巡检使用，**不得** delete-then-insert 全量替换（会清掉用户未保存的目标 Tag）
- [x] 9.2.3 将 `checkAndSyncEnvironment` 改造为巡检入口：仅对 `enabled` 且 `targetTag` 非空的行比对；`muted` 行跳过通知但仍更新 `currentTag`；锁定模式回写后**重新读取文件**取回写后的实际值
- [x] 9.2.4 新增 `ArgoCdChangeEvent` 与 `Stream<ArgoCdChangeEvent>` 事件流（替代原版 `listen('argocd-tag-changed')`），变更时推送并供 UI 实时刷新
- [x] 9.2.5 单元测试：merge 保留用户字段、id 稳定性、upsert 不清空 targetTag、muted 行跳过通知但写 currentTag

### 9.3 后台巡检调度接入

- [x] 9.3.1 在 `SchedulerService` 中接入 ArgoCD 巡检循环（与任务调度同一生命周期，由 `start()` 统一拉起）
- [x] 9.3.2 实现 `getMinArgoCdInterval`：取启用环境 `MIN(cron_expr)` 作为下次唤醒间隔，无启用环境时回退 300 秒；环境增删改后循环自校正，无需重启
- [x] 9.3.3 仅 `enabled = 1` 的环境纳入巡检；单环境异常（登录失败、API 报错）记录日志并跳过，不中断整体循环
- [ ] 9.3.4 集成验证（**未做**）：配置环境并启用后，后台按间隔自动更新 `current_tag` 与 `last_checked`，无需人工点击扫描。需要真实 GitLab 内网可达（当前本机无法解析 `gitlab.example.internal`，DB 中已有 env-sit / env-lock 两个演示环境但从未跑过一次巡检，`last_checked` 全为空），接入内网或 VPN 后执行

### 9.4 通知通道

- [x] 9.4.1 实现宿主 OS 原生通知发送（macOS `osascript display notification`，与 `asset_reminder_service.dart` 既定模式一致），标题固定「ArgoCD Tag 变更」，正文为变更消息
- [x] 9.4.2 `muted` 行跳过通知调用但保留 DB 更新；锁定模式通知正文追加「(已自动修复)」
- [x] 9.4.3 通知发送失败仅记日志，不中断巡检循环

### 9.5 UI 对齐原交互（`ui/ops_devops_view.dart` Tab 4）

- [x] 9.5.1 替换 `_checkResults` 快照模型为持久化 `_tags` 配置列表，选中环境切换时 `loadArgoCdTags` 载入
- [x] 9.5.2 补齐三个操作按钮：`刷新 Tag`（loading 态 + 成功/失败提示）、`复制当前到目标`、`保存 Tag 配置`
- [x] 9.5.3 Tag 表补齐 7 列：项目 / 当前 Tag（只读 code 样式）/ 目标 Tag（**内联可编辑**）/ 关闭弹窗提醒（Checkbox）/ 状态（一致·绿、不一致·红、未设定·灰）/ 是否启用（Switch）
- [x] 9.5.4 不一致行高亮（当前 Tag ≠ 目标 Tag 且目标非空时），对应原版 `tag-blink` 动画效果
- [x] 9.5.5 监听 `ArgoCdChangeEvent` 实时刷新当前环境行，取代人工重扫
- [x] 9.5.6 环境列表支持**编辑**（复用新增弹窗并回填字段）与**删除**（`deleteArgoCdEnv`，删除后清空当前选择）
- [x] 9.5.7 环境弹窗补齐字段：`gitlabUsername`、`gitlabPassword`（原版有，迁移版弹窗缺失，导致非 PAT 的 Session 登录环境无法工作）、`cronExpr` 8 档（10s/30s/1m/2m/5m/10m/30m/1h）、`enabled` 开关；新建默认 `enabled=false`
- [x] 9.5.8 环境详情卡展示监控模式（监控/锁定）、GitLab URL、配置仓路径、检查频率（秒数转人读格式）
- [x] 9.5.9 空态文案：未选环境时提示「请先选择或创建一个 ArgoCD 环境」
- [x] 9.5.10 回勾 2.3 与 6.3，并运行 `flutter analyze --no-fatal-infos` 与 `flutter test test/ops_tool_test.dart` 确认全绿
