## Purpose

让 Security Agent 的工具调用真正落到执行层：每一次 `run_*` 都对应一次真实的工具执行，结果写回会话资产/发现物/时间线，而不是只在日志里留一行。用户以审批者角色监督高影响操作，但低影响的侦察类工具应当直接拿到可用数据。

## MODIFIED Requirements

### Requirement: 安全工具 Agent 工具集

系统 SHALL 将以下安全操作封装为 AgentLoop 可调用的工具，供 AI 按需调用：`run_nmap(target, options)`、`run_nuclei(targets, templates)`、`run_subfinder(domain)`、`run_httpx(targets)`、`run_ffuf(url, wordlist)`、`run_sqlmap(url)`、`run_msf_module(module, options)`、`query_threat_intel(keyword)`、`get_session_findings()`。

每个工具的返回内容 SHALL 是该工具本次执行的真实结果摘要（结构化字段 + 条数），而非"已记录"之类的占位文本。返回文本 SHALL 截断到 500 字符以内，避免多轮迭代撑爆上下文。

#### Scenario: AI 调用扫描工具并拿到真实结果

- **WHEN** Security Agent 决定对目标执行端口扫描
- **THEN** 系统 SHALL 通过 AgentLoop 执行 `run_nmap` 工具调用，实时展示工具执行状态
- **AND** 返回给模型的文本 SHALL 包含实际发现的开放端口、服务名与版本
- **AND** 扫描结果 SHALL 自动写入当前会话的资产清单，并在时间线追加一条 `tool_run` 事件

#### Scenario: 未安装工具时模型拿到 actionable 的失败原因

- **WHEN** Agent 调用 `run_nuclei` 但本机未安装 nuclei
- **THEN** 返回给模型的文本 SHALL 说明"未检测到 nuclei，请先在工具状态面板安装"
- **AND** Agent SHALL 能够基于该信息调整后续步骤（例如改用已安装的 nmap），而不是反复重试同一个工具

#### Scenario: 无会话时拒绝执行

- **WHEN** 用户在没有创建会话的情况下启动 Agent 并让它扫描
- **THEN** 系统 SHALL 返回"请先创建会话"给模型
- **AND** 不产生任何数据库写入

### Requirement: Agent 执行透明度

系统 SHALL 实时展示 Agent 的"思考过程"：当前步骤、选择该工具的原因、工具执行状态、中间分析结论，用户可在任意时刻查看完整的 Agent 决策日志。

#### Scenario: 每一步工具调用可追溯

- **WHEN** Agent 完成一次 `run_nmap` 调用
- **THEN** Agent 日志中 SHALL 显示该工具的名称、参数、执行结果摘要（成功或失败原因）
- **AND** 用户 SHALL 能在时间线视图中找到对应的 `tool_run` 事件，二者内容一致

#### Scenario: 高影响操作跳过时不产生数据

- **WHEN** 用户跳过了 Agent 请求的 `run_msf_module` 调用
- **THEN** Agent 日志 SHALL 标注该步骤为"用户跳过"
- **AND** 会话中 SHALL 不出现对应的执行记录或 Finding
