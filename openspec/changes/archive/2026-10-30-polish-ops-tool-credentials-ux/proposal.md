## Why

`integrate-fs-ops-tool` 落地后，运维工具的三个凭据相关交互与宿主管护工具的水准有明显落差，直接影响日常可用性：ArgoCD 监控环境的编辑入口是一个 13×13 px 的铅笔图标，夹在环境名与启用开关之间、无 tooltip、无 hover 态，用户感知为「只能切换不能编辑」；六个敏感字段（DevOps 连接密码、GitLab PAT、ArgoCD 环境密码与 Token、邮箱授权码、数据源密码）全部硬编码 `obscureText: true` 且没有显示/隐藏切换，用户输错一位只能整框重敲；ArgoCD 环境编辑弹窗还会把已保存的密码与 Token 明文回填进输入框，既违反宿主「已安全保存，若不修改请留空」的既定惯例，也让改一个频率字段不得不重新过一遍密钥。

同时，`ops_tool.db` 中遗留了两个从未可用的演示环境（`gitlab_url` 指向不存在的 `gitlab.example.internal`、凭据全空、`enabled = 1`），会持续触发巡检失败日志并干扰真实环境的验证。这两行数据与上一 change 的验收任务 9.3.4 直接相关，需要在同一次改动中清掉，使「启用环境」集合只反映真实配置。

## What Changes

- **ArgoCD 监控环境编辑入口可发现化**：环境 chip 的编辑与删除操作从「图标即功能」改为带 tooltip 的显式图标按钮，编辑入口在选中环境的详情卡上额外提供一个「编辑环境」文字按钮；删除增加确认步骤，避免误触清空整张 Tag 配置表（外键级联）。
- **凭据字段统一支持显示/隐藏切换**：ops_tool 全部六个敏感输入框补齐眼睛按钮，沿用宿主 `ai_config_page.dart` 的 `Icons.visibility` / `Icons.visibility_off` + tooltip 范式；GitLab PAT 字段当前**完全没有脱敏**（明文常显），本次一并修正为默认脱敏。
- **编辑态凭据不再回填**：ArgoCD 环境与 DevOps 连接编辑弹窗改为「留空则保持原值不变」语义，与 `ai_config_page.dart` 的 API Key 编辑惯例对齐；保存时仅在字段非空时写入，空值保留数据库中的既有凭据。
- **清理演示环境**：删除 `argocd_environments` 中 `gitlab_url` 无法解析且凭据全空的演示行及其级联 Tag 数据，并在此后新增一条针对「环境凭据为空时不允许启用」的前置校验，避免再次产生同类不可用配置。

## Capabilities

### New Capabilities

<!-- 无新增能力：本 change 只修订既有能力的交互与安全要求。 -->

### Modified Capabilities

- `ops-tool`: 修订「DevOps ArgoCD 镜像标签监控与防漂移锁定」中环境新增/编辑场景的要求（编辑入口可发现、删除需确认、编辑态凭据不回填），并新增「凭据字段脱敏与可切换显示」的通用要求，覆盖 GitLab/Jenkins 连接、ArgoCD 环境与邮件账户三类凭据入口。

## Impact

- **涉及代码**：`lib/tools/ops_tool/ui/ops_devops_view.dart`（环境 chip、环境弹窗、连接弹窗）、`lib/tools/ops_tool/ui/ops_email_view.dart`（SMTP 授权码）、`lib/tools/ops_tool/ui/ops_datasource_view.dart`（数据源密码）；`lib/tools/ops_tool/services/scheduler_service.dart` 与巡检入口需在凭据缺失时给出可归因的跳过原因而非静默失败。
- **数据**：一次性清理 `ops_tool.db` 的演示环境行（`DELETE` + 外键级联），不迁移旧工具 `com.fs-ops-tool.app` 的任何数据。
- **安全边界**：本 change **不改变**凭据的存储形态——`argocd_environments.gitlab_password` / `gitlab_token` 与 `email_accounts.password_encrypted`（列名已存在但实际为明文写入）仍为明文 SQLite。接入宿主 `KeychainService` + DEK 体系属于独立的架构变更，需处理存量数据的解密重加密，另开 change。
- **依赖**：无新增第三方依赖。
