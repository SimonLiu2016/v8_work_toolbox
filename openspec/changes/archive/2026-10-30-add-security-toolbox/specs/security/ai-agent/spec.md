## Purpose

通过将安全工具封装为 AI 可调用的工具（基于现有 AgentLoop），使 AI 能自主驱动多阶段渗透测试工作流，自动完成侦察→扫描→分析→利用的完整流程，用户以审批者角色监督关键决策节点。

## ADDED Requirements

### Requirement: 安全工具 Agent 工具集

系统 SHALL 将以下安全操作封装为 AgentLoop 可调用的工具，供 AI 按需调用：`run_nmap(target, options)`、`run_nuclei(targets, templates)`、`run_subfinder(domain)`、`run_httpx(targets)`、`run_ffuf(url, wordlist)`、`run_sqlmap(url)`、`run_msf_module(module, options)`、`query_threat_intel(keyword)`、`get_session_findings()`。

#### Scenario: AI 调用扫描工具

- **WHEN** Security Agent 决定对目标执行端口扫描
- **THEN** 系统 SHALL 通过 AgentLoop 执行 `run_nmap` 工具调用，实时展示工具执行状态，结果自动写入会话

### Requirement: 自然语言任务驱动

系统 SHALL 支持用户用中文或英文自然语言描述渗透目标（如"对这个局域网做完整的渗透测试"），Security Agent 自动分解为具体工具调用序列执行。

#### Scenario: 一键局域网渗透

- **WHEN** 用户输入"扫描 192.168.1.0/24 局域网，找出所有可利用漏洞"并点击"启动 Agent"
- **THEN** Security Agent SHALL 自动按顺序执行：ARP 发现 → nmap 深度扫描 → nuclei 漏洞扫描 → AI 分析优先级 → 推荐利用方案，每步完成后更新进度

#### Scenario: 一键 Web 渗透

- **WHEN** 用户输入域名并描述"全面评估 example.com 的 Web 安全"
- **THEN** Security Agent SHALL 按顺序执行：subfinder → httpx → katana + ffuf → nuclei → sqlmap（含参数 URL），并在结束后生成初步报告摘要

### Requirement: 人工审批关键操作

系统 SHALL 在 Agent 准备执行具有"破坏性"或"高影响"的操作（如 exploit 利用、密码爆破）前，暂停并向用户展示"AI 建议执行 X 操作，原因：Y，是否确认？"，仅在用户点击"确认"后继续。

#### Scenario: Exploit 操作审批

- **WHEN** Security Agent 决定对 192.168.1.105 执行 EternalBlue exploit
- **THEN** 系统 SHALL 暂停 Agent，向用户展示操作详情（目标、模块、预期效果），等待用户点击"确认执行"或"跳过"

### Requirement: Agent 执行透明度

系统 SHALL 实时展示 Agent 的"思考过程"：当前步骤、选择该工具的原因、工具执行状态、中间分析结论，用户可在任意时刻查看完整的 Agent 决策日志。

#### Scenario: Agent 状态面板

- **WHEN** Security Agent 正在运行
- **THEN** 系统 SHALL 在界面显示当前步骤（如"步骤 3/7：执行 nuclei 漏洞扫描"）和 Agent 的最新分析文字，工具执行日志实时滚动展示

### Requirement: Agent 中断与恢复

系统 SHALL 支持随时暂停正在运行的 Security Agent，已完成的步骤和 Finding 保留，用户可在任意时间点选择从当前状态继续或重置 Agent。

#### Scenario: Agent 暂停

- **WHEN** 用户点击"暂停 Agent"
- **THEN** 系统 SHALL 完成当前正在执行的工具调用后停止，已有数据全部保留，显示"已暂停，可继续"状态
