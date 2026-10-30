## Why

将独立的 Tauri/Rust 运维工具「FS-OPS-Tool（磐石运维工具）」完整迁移并重构集成至 V8WorkToolbox 桌面套件中，使开发者在一个统一的应用内即可完成 DevOps 流水线操作（GitLab/Jenkins/ArgoCD）、多源运营数据汇聚与 Excel 报告自动生成及邮件定时调度。同时，通过复用 V8WorkToolbox 已有的全局统一 AI 配置与 Keychain 密钥服务，彻底消除原工具孤立配置 AI 模型的痛点。

## What Changes

- **新增独立子窗口与工具入口**：在 `ToolRegistry` 注册「磐石运维工具（ops-tool）」，支持通过 `desktop_multi_window` 以独立大窗口（1200x800）启动，配置完整的侧边栏导航与统一深色风格。
- **引入纯 Dart 核心能力依赖**：在 `pubspec.yaml` 中增加 `excel: ^4.0.6`（Excel 多 Sheet 解析）、`mailer: ^6.1.2`（SMTP 邮件发送）、`cron: ^0.5.1`（定时调度表达式引擎）。
- **统一本地 SQLite 持久化**：在 `~/Library/Application Support/V8WorkToolbox/ops_tool/` 下建立本地数据库 `ops_tool.db`，承载连接配置、数据源、SQL 模板、报告与模板、定时任务及日志、ArgoCD 监控环境等完整数据模型。
- **DevOps 运维流水线引擎**：
  - GitLab 客户端：项目组与通配符过滤、跨组多选、批量创建分支、`pom.xml` 版本批量递增与 Commit 提交（支持 GitLab v3/v4 自动兼容回退）。
  - Jenkins 客户端：CSRF Crumb 自动提取、参数化构建触发与轮询任务状态。
  - ArgoCD 镜像监控器：**按环境管理可编辑的 Tag 配置表**（当前 Tag / 目标 Tag / 关闭提醒 / 是否启用逐行维护），后台按环境最小间隔常驻巡检，支持配置仓路径解析（`/tree/<branch>/<dir>`）、监控告警模式与锁定修复模式。
- **多数据源与报告模板引擎**：
  - 数据源适配：支持 PingCode（Session 保持与工作项过滤）、Grafana（看板与查询代理）、PhpMyAdmin / SQL 查询管理。
  - 纯 Dart 模板引擎：支持单元格精准坐标引用（如 `B3`）、列聚合统计（sum/count/avg/max/min）与数据库 SQL 结果占位符动态填充。
  - 报告中心：Markdown 交互式编辑、分节预览与 HTML 邮件内容导出。
- **定时调度与邮件服务**：基于 Cron 表达式的后台调度循环，支持定时自动拉取数据、渲染报告并触发 SMTP 发信，记录全量执行日志。
- **全局 AI 赋能**：报告异常研判、报告摘要生成与运维对话直接调用宿主 `AiService` 与 `AiConfigStore`，使用宿主默认文本模型与安全 Key，无需单独配置。

## Capabilities

### New Capabilities
- `ops-tool`: 磐石运维自动化工具，覆盖 DevOps 流水线管理（GitLab/Jenkins/ArgoCD）、多数据源与 Excel 报告模板引擎、SMTP 邮件发送与 Cron 调度，并无缝接入宿主全局 AI 能力。

### Modified Capabilities
<!-- No requirement changes to existing capabilities -->

## Impact

- **依赖项变更**：新增 `excel`、`mailer`、`cron` 纯 Dart 库。
- **窗口与进程拓扑**：`main.dart` 注册新的 `WindowKind.opsTool`，继承 `SettingsStore`, `ProxySettings`, `AiConfigStore` 拓扑依赖。
- **持久化隔离**：用户运维数据独立保存在应用支持目录子路径 `ops_tool/ops_tool.db`，不影响已有密码库或笔记数据。
