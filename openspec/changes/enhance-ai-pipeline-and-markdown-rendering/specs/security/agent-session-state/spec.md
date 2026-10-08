## MODIFIED Requirements

### Requirement: Agent 工具调用真实执行
系统中 SecurityAgentExecutor 提供给 AgentLoop 的工具执行回调 SHALL 驱动真实的本地 CLI 工具（NmapService、NucleiService、SqlmapService 等），并将工具结果写入当前会话数据库；同时将结果截断为不超过 500 字符的摘要回灌给 AI，防止 context 膨胀。工具调用不再是 dry-run 存根。

#### Scenario: Agent 调用 run_nmap
- **WHEN** AI 通过 AgentLoop 发出 run_nmap 工具调用
- **THEN** 系统调用 NmapService.scan()，将发现的主机与端口写入 assets 数据库，并向 AI 返回不超过 500 字符的端口服务摘要

#### Scenario: Agent 调用 run_nuclei
- **WHEN** AI 通过 AgentLoop 发出 run_nuclei 工具调用
- **THEN** 系统调用 NucleiService.scan()，将发现物写入 findings 数据库，并向 AI 返回不超过 500 字符的漏洞摘要

#### Scenario: Agent 调用 get_session_findings
- **WHEN** AI 通过 AgentLoop 发出 get_session_findings 工具调用
- **THEN** 系统从数据库读取当前会话的全部发现物，返回严重度分布与标题列表摘要（不超过 500 字符）
