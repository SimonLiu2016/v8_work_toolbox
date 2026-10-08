## Purpose

实时追踪公开漏洞情报（CVE、KEV、GitHub PoC），由 AI 对新漏洞进行摘要分析并与当前会话资产交叉比对，以日报和推送两种形式将最新威胁信息传递给安全工程师。

## ADDED Requirements

### Requirement: CVE 实时追踪

系统 SHALL 定期（默认每 4 小时）从以下来源同步最新漏洞数据：NVD API（`/cves/2.0`）、CISA KEV（已知被利用漏洞目录）、CNA 发布的 CVE JSON feeds。同步后按严重等级存储至本地缓存。

#### Scenario: 首次同步

- **WHEN** 用户首次打开威胁情报面板
- **THEN** 系统 SHALL 自动触发增量同步，获取最近 7 天的 CVE 数据，展示同步进度

#### Scenario: CISA KEV 优先展示

- **WHEN** 同步数据中包含 CISA KEV 中的已利用漏洞
- **THEN** 系统 SHALL 在列表顶部以特殊样式标注 KEV 漏洞，表明其已在野外被利用

### Requirement: GitHub PoC 监控

系统 SHALL 通过 GitHub Search API 监控新发布的 PoC 仓库，搜索关键词包含最新 CVE 编号，检测到新 PoC 后记录仓库地址、Star 数、首次出现时间。

#### Scenario: PoC 发现通知

- **WHEN** GitHub 出现针对某个 High/Critical CVE 的新 PoC 仓库
- **THEN** 系统 SHALL 在情报列表中该 CVE 条目旁显示"PoC 可用"徽章，并记录 GitHub 链接

### Requirement: AI 漏洞日报生成

系统 SHALL 每日（默认 09:00）生成 AI 威胁情报日报，内容包含：过去 24 小时新增 Critical/High 级别 CVE 摘要、CISA KEV 新增条目、与当前会话资产相关的漏洞高亮（交叉比对）、AI 建议优先关注的漏洞。

#### Scenario: 日报生成

- **WHEN** 定时任务触发 AI 日报生成
- **THEN** 系统 SHALL 将新 CVE 数据和当前会话资产列表发送给 AI，AI 输出 500 字内的中文摘要，存储并显示在情报面板

### Requirement: 资产交叉比对

系统 SHALL 自动将情报库中的 CVE 与当前会话资产的技术栈和版本信息进行比对，当某资产的服务版本命中已知 CVE 时，自动生成 Finding 并关联至对应资产。

#### Scenario: 自动漏洞关联

- **WHEN** 情报库同步到 CVE-2024-1234（影响 Apache 2.4.x），且当前会话存在 Apache 2.4.51 的资产
- **THEN** 系统 SHALL 在该资产下自动创建 Finding 条目，状态为"待验证"，来源标注为"情报匹配"

### Requirement: 情报搜索与过滤

系统 SHALL 支持在情报库中按 CVE 编号、关键词、CVSS 评分范围、漏洞类型（RCE/SQLi/XSS/LPE 等）、时间范围过滤搜索，结果实时更新。

#### Scenario: 关键词搜索

- **WHEN** 用户在情报面板搜索框输入 "nginx"
- **THEN** 系统 SHALL 展示所有与 nginx 相关的 CVE，按 CVSS 降序排列
