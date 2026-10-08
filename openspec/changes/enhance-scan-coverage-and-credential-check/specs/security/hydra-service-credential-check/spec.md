## Purpose

对目标主机上开放的系统服务（SSH、FTP、HTTP-Basic 等）执行弱口令合规基线核查，发现使用常见弱密码的服务账号并以 critical 发现物写入数据库。

## ADDED Requirements

### Requirement: 服务层弱口令核查执行
系统 SHALL 能够对指定主机 IP 和端口上运行的网络服务（SSH/FTP/HTTP-Basic）执行弱口令核查，使用内置基线弱口令字典尝试认证，并将命中结果实时写入当前会话的 findings 数据库。

#### Scenario: SSH 服务弱口令核查命中
- **WHEN** 对目标主机 SSH 端口（22）执行弱口令核查，且该主机使用了 `root:123456` 或类似弱凭据
- **THEN** 系统将该发现以 `critical` 严重度写入 findings，记录目标 IP、端口、服务类型、命中的账号密码组合

#### Scenario: 无弱口令时安全返回
- **WHEN** 对目标主机执行弱口令核查，字典全部尝试完毕均未命中
- **THEN** 系统返回"未发现弱口令"结论，不写入任何 finding

### Requirement: Agent 可调度弱口令核查
AI Agent 研判层 SHALL 能够通过 `run_hydra` 工具调用发起服务层弱口令核查，工具参数须包含目标地址和服务类型。

#### Scenario: AI Agent 调用 run_hydra
- **WHEN** AI 通过 AgentLoop 发出 `run_hydra` 工具调用，指定 target 和 service
- **THEN** 系统调用底层 HydraService，将结果写库，并向 AI 返回不超过 500 字符的摘要

### Requirement: 执行安全约束
弱口令核查工具 SHALL 在执行时受以下约束：每个服务目标的尝试次数不超过内置字典大小（≤ 100 条），执行完毕后自动停止，不持续爆破。

#### Scenario: 字典耗尽自动停止
- **WHEN** 弱口令字典的所有条目已对目标服务全部尝试完毕
- **THEN** 进程自动退出，不再继续发送认证请求
