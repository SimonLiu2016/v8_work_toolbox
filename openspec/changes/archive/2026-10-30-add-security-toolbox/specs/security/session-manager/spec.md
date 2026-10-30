## Purpose

管理一次完整渗透测试工作的生命周期：从建立目标范围，到追踪扫描进度、资产清单、漏洞发现物和 AI 分析结论，并维护可查询的操作时间线，支持最终报告生成。

## ADDED Requirements

### Requirement: 会话创建与配置

系统 SHALL 支持创建类型为 `lan`（局域网）或 `web`（公网 Web 资产）的渗透会话，并记录：会话名称、类型、目标范围（CIDR 列表或域名列表）、创建时间、状态（进行中 / 暂停 / 完成）。

#### Scenario: 创建 LAN 会话

- **WHEN** 用户选择"新建会话 → 局域网"并输入目标 CIDR（如 `192.168.1.0/24`）
- **THEN** 系统 SHALL 创建新会话，自动填充本机当前所在网段，并持久化至本地数据库

#### Scenario: 创建 Web 会话

- **WHEN** 用户选择"新建会话 → Web 资产"并输入目标域名（如 `example.com`）
- **THEN** 系统 SHALL 创建新会话，支持输入多个根域名

### Requirement: 资产清单管理

系统 SHALL 在会话内维护发现资产的清单，LAN 会话的资产为主机（IP、MAC、OS、开放服务），Web 会话的资产为子域名/URL（域名、IP、HTTP 状态码、技术栈）。

#### Scenario: 资产自动录入

- **WHEN** 任意侦察工具（nmap / subfinder / httpx）完成扫描
- **THEN** 系统 SHALL 解析工具 JSON 输出，自动将发现的资产合并写入会话资产清单，去重已存在的条目

#### Scenario: 资产手动标注

- **WHEN** 用户在资产清单中选中某条目并编辑备注
- **THEN** 系统 SHALL 保存用户自定义标注，且不受后续扫描覆盖

### Requirement: 漏洞发现物追踪

系统 SHALL 记录每个会话的漏洞发现物（Finding），每条记录包含：关联资产、CVE 编号（可选）、漏洞名称、CVSS 评分、严重等级（Critical/High/Medium/Low/Info）、状态（待验证 / 已确认 / 已利用 / 误报）、证据文本、发现时间。

#### Scenario: 漏洞自动录入

- **WHEN** nuclei 或 metasploit 扫描完成
- **THEN** 系统 SHALL 将输出的每个发现解析为 Finding 条目，按严重等级排序展示

#### Scenario: 漏洞状态变更

- **WHEN** 用户将某 Finding 标记为"已利用"
- **THEN** 系统 SHALL 记录状态变更时间，并更新会话摘要中的利用计数

### Requirement: 操作时间线

系统 SHALL 以时间顺序记录会话内的所有操作事件：工具执行（命令、参数、耗时）、AI 分析（输入摘要、结论）、状态变更（资产新增、Finding 状态改变）。

#### Scenario: 时间线查看

- **WHEN** 用户切换至"时间线"视图
- **THEN** 系统 SHALL 按时间倒序展示所有事件，支持按类型过滤

### Requirement: 会话持久化与恢复

系统 SHALL 将会话数据持久化至本地 SQLite（drift），应用重启后可恢复最近一次进行中的会话状态，包括所有资产、Finding 和时间线记录。

#### Scenario: 会话恢复

- **WHEN** 用户重新启动应用并打开安全工具箱
- **THEN** 系统 SHALL 自动恢复上次进行中的会话，展示其资产和 Finding 清单
