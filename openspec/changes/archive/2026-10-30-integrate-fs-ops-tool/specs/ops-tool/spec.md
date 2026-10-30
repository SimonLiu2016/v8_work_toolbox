## Purpose

提供集成式的 DevOps 运维与运营报告自动化工具箱，支持 GitLab/Jenkins/ArgoCD 流水线操作、多源运营数据采集与 Excel 报告模板渲染、SMTP 邮件定时分发，并与宿主全局 AI 能力无缝协同。

## ADDED Requirements

### Requirement: 运维小工具入口与多窗口生命周期
系统 SHALL 在主启动器中注册「磐石运维工具」，且支持在独立的桌面子窗口中以深色卡片风格完整渲染多标签控制台。

#### Scenario: 独立窗口呼出
- **WHEN** 用户在主工具箱列表中点击「磐石运维工具」或按下回车
- **THEN** 系统呼出尺寸为 1200x800 的独立桌面窗口，展示侧边栏导航与仪表盘概览，且主进程环境与代理/AI配置同步生效

### Requirement: DevOps GitLab 项目管理与批量操作
系统 SHALL 允许用户配置 GitLab 连接，按 Group 检索项目列表，并支持跨项目批量创建分支与批量递增 pom.xml 版本号。

#### Scenario: 批量创建分支
- **WHEN** 用户勾选多个 GitLab 项目并输入源分支与新分支名称执行创建
- **THEN** 系统并发调用 GitLab API 创建对应分支，并在操作日志中反馈每个项目的创建成功或失败详情

#### Scenario: 批量更新 pom.xml 版本
- **WHEN** 用户勾选多个 Maven 项目并指定目标版本号及 Commit Message 执行更新
- **THEN** 系统读取项目根目录下的 pom.xml，定位并修改版本字段后向目标分支提交 commit

### Requirement: DevOps Jenkins 构建触发与状态追踪
系统 SHALL 允许用户配置 Jenkins 连接，支持自动获取 CSRF Crumb 并对选定项目发起参数化构建与状态追踪。

#### Scenario: 触发 Jenkins 构建
- **WHEN** 用户为选定项目选择构建分支及参数后点击触发构建
- **THEN** 系统携带 Crumb 发起构建请求，并展示轮询到的构建状态（排队中/构建中/成功/失败）

### Requirement: DevOps ArgoCD 镜像标签监控与防漂移锁定
系统 SHALL 支持按环境管理 GitLab 配置仓中的镜像 Tag 配置，提供可编辑的 Tag 配置表，并在后台按环境配置的间隔持续巡检、比对与告警。`argocd_tags` 是用户维护的配置表：`target_tag` 由用户写入，`current_tag` 由扫描与巡检写入，二者语义不得互换。

#### Scenario: 新增与编辑监控环境
- **WHEN** 用户新建或编辑监控环境并填写环境名称、GitLab URL、用户名、密码、Token（可选）、配置仓路径、监控模式与检查频率
- **THEN** 系统保存环境配置并支持随时修改、启停与删除；启用状态为启用的环境才会纳入后台巡检

#### Scenario: 刷新 Tag 并与已有配置合并
- **WHEN** 用户选中环境后点击「刷新 Tag」
- **THEN** 系统拉取配置仓内全部 YAML 文件的 Image Tag，按项目名与已有配置合并（保留已填的目标 Tag、关闭提醒开关与启用状态），写回配置表并在界面展示「已刷新 N 个 Tag」
- **AND** 若配置仓文件数超过单页上限，系统 SHALL 通过 `Link: rel="next"` 逐页翻完，不得静默截断

#### Scenario: 批量设定目标 Tag
- **WHEN** 用户点击「复制当前到目标」
- **THEN** 系统将配置表中每一行的当前 Tag 写入该行的目标 Tag，作为后续比对的基准值

#### Scenario: 逐行编辑与保存 Tag 配置
- **WHEN** 用户在目标 Tag 列内联修改、切换「关闭弹窗提醒」或「是否启用」后点击「保存 Tag 配置」
- **THEN** 系统将配置表整体持久化，并提示「Tag 配置已保存」

#### Scenario: 后台巡检与不一致提示
- **WHEN** 后台巡检按启用环境中最小的检查间隔触发，发现某项目当前 Tag 与目标 Tag 不一致且该行未被关闭提醒与未被停用
- **THEN** 系统将该行标记为不一致状态并在界面高亮提醒，同时通过操作系统原生通知弹出变更消息，并仅更新该行的当前 Tag 与最后检查时间而不改动用户填写的目标 Tag

#### Scenario: 监控模式仅告警
- **WHEN** 环境处于监控模式且检测到 Tag 偏离
- **THEN** 系统仅记录告警日志并通知提醒，不修改配置仓中的任何文件

#### Scenario: 锁定模式自动回写
- **WHEN** 环境处于锁定模式且检测到 Tag 偏离
- **THEN** 系统自动向配置仓提交修复 Commit 将 Tag 恢复为目标值，记录修复日志并在通知中标注「已自动修复」

#### Scenario: 关闭提醒的环境仍更新数据
- **WHEN** 某项目被标记为关闭弹窗提醒，巡检发现其 Tag 偏离
- **THEN** 系统跳过通知但仍更新该行的当前 Tag，保持数据实时性

### Requirement: 多源数据采集与 SQL 模板
系统 SHALL 支持配置 PingCode、Grafana 及数据库 (PhpMyAdmin/SQL) 数据源，并提供可复用的 SQL 查询模板及测试执行。

#### Scenario: 执行数据源查询
- **WHEN** 用户选择已保存的数据源并执行查询或测试连接
- **THEN** 系统通过安全 HTTP 会话获取响应，并以表格形式实时呈现查询结果数据

### Requirement: Excel 文件解析与模板引擎渲染
系统 SHALL 支持解析本地 Excel 文件（多 Sheet），并根据预设抽取规则（单元格引用、列统计聚合、数据库结果填充）将数据渲染为格式化报告。

#### Scenario: 根据模板渲染生成报告
- **WHEN** 用户导入包含多 Sheet 的 Excel 文件并选择报告模板执行生成
- **THEN** 系统解析单元格和聚合公式，自动替换模板占位符生成完整的 Markdown 分节内容

### Requirement: 报告中心与 HTML 邮件导出
系统 SHALL 提供 Markdown 报告编辑、分节管理（销售总览、服务自动化、异常告警等）及一键渲染为 HTML 邮件格式。

#### Scenario: 导出为邮件 HTML
- **WHEN** 用户在报告中心点击导出或准备发送邮件
- **THEN** 系统将 Markdown 转换为带内联样式的排版精美 HTML 邮件正文并流转至邮件模块

### Requirement: 邮件账户管理与 SMTP 发信
系统 SHALL 支持配置多个 SMTP 账户（支持 TLS 加密）及通讯录分组，并可直接投递生成的 HTML 报告邮件。

#### Scenario: 测试与发送报告邮件
- **WHEN** 用户选择发件账户、勾选收件人分组并点击发送
- **THEN** 系统建立 SMTP TLS 连接完成邮件投递，并提示发信成功及记录发信流水

### Requirement: 定时任务调度与执行日志
系统 SHALL 支持基于 Cron 表达式在后台定时执行数据拉取、报告生成及邮件自动分发，并持久化记录每次执行的状态与耗时。

#### Scenario: 定时任务触发执行
- **WHEN** 系统后台调度时钟匹配定时任务的 Cron 表达式
- **THEN** 系统自动串行执行抓取、生成与发信流程，并将执行结果写入任务日志表

### Requirement: 接入宿主全局 AI 研判与生成
系统 SHALL 直接复用宿主全局统一的 AI 供应商配置（AiConfigStore 与 AiService），对报告异常指标研判、提炼总结和智能问答。

#### Scenario: 报告异常智能研判
- **WHEN** 用户在报告分节中点击「AI 研判」或生成摘要
- **THEN** 系统读取当前宿主默认启用的文本模型与配置发起流式/完整生成，将研判结论无缝插入报告，无需用户额外配置 API Key
