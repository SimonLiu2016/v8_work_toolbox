## Purpose

让情报交叉比对真正落库：命中当前会话资产的 CVE 不再只是横幅上的一行提示，而是可以一键成为可追踪的 Finding（状态"待验证"、来源"情报匹配"），进入与 nuclei / msf 发现物同一套状态流转。同时把 daily digest 的产出接到实际调度上，让 09:00 的日报真的有内容可看。

## MODIFIED Requirements

### Requirement: 资产交叉比对

系统 SHALL 自动将情报库中的 CVE 与当前会话资产的技术栈和版本信息进行比对，当某资产的服务版本命中已知 CVE 时，自动生成 Finding 并关联至对应资产。

#### Scenario: 命中后一键落库

- **WHEN** 情报同步完成且交叉比对发现资产命中某 CVE
- **THEN** 系统 SHALL 在情报面板以高亮横幅提示命中数量与具体 CVE → 资产对应关系
- **AND** 提供"生成 Finding"操作，用户点击后 SHALL 为每个命中创建 Finding，状态为"待验证"，来源标注"情报匹配"，并关联至对应资产

#### Scenario: 不自动刷噪音

- **WHEN** 一次情报同步命中大量资产（例如首次同步 7 天 CVE）
- **THEN** 系统 SHALL NOT 自动批量创建 Finding，只提示并等待用户确认
- **AND** 用户确认后创建的 Finding SHALL 与手工创建的 Finding 在列表、筛选、报告聚合中一视同仁

#### Scenario: 已存在的命中不重复创建

- **WHEN** 用户对同一命中再次点击"生成 Finding"
- **THEN** 系统 SHALL 识别该 资产+CVE 组合的 Finding 已存在并跳过，不产生重复条目

### Requirement: AI 漏洞日报生成

系统 SHALL 每日（默认 09:00）生成 AI 威胁情报日报，内容包含：过去 24 小时新增 Critical/High 级别 CVE 摘要、CISA KEV 新增条目、与当前会话资产相关的漏洞提示、AI 建议优先关注的漏洞。

#### Scenario: 日报有真实内容可看

- **WHEN** 每日 09:00 的定时任务触发且过去 24 小时有新同步的 CVE
- **THEN** 系统 SHALL 生成本次日报、追加到本地日报列表（不覆盖历史），并在情报面板可回看至少最近 7 天的日报

#### Scenario: 无新数据时静默跳过

- **WHEN** 过去 24 小时没有新同步的 CVE
- **THEN** 系统 SHALL 跳过本次日报生成，不在日报列表插入空条目
