## Purpose

管理 Dola 视频生成平台的多账号凭证，跟踪每日生成配额、状态机生命周期、代理绑定与高并发负载均衡调度。

## ADDED Requirements

### Requirement: Account Credential Storage and Security
系统 SHALL 安全存储 Dola 平台账号凭证（包含 sessionid / cookies），敏感字段通过平台钥匙串服务隔离保存，非敏感元数据持久化于应用支持目录。

#### Scenario: User imports cookies
- **WHEN** 用户批量粘贴一个或多个 Dola 账号的 Cookie 文本并提交
- **THEN** 系统解析并校验 sessionid 字段，将每个账号的安全凭据存入钥匙串，元数据建立本地索引记录并标记为初始状态

### Requirement: Account Lifecycle and Quota Management
系统 SHALL 维护账号的多维状态机（满额、半额、冷却、生成中、风控、异常），并在每日东京时间 0 点（北京时间 23:00）自动重置当日配额。

#### Scenario: Account quota consumption
- **WHEN** 某个满额账号（拥有 4 点额度）执行了一次 Seedance 2.5 视频生成任务（消耗 2 点）
- **THEN** 任务成功后系统将该账号剩余点数更新为 2 点，状态变更为半额，可继续参与后续生成调度

#### Scenario: Daily quota reset
- **WHEN** 系统时钟越过东京时间 0 点（JST 00:00）
- **THEN** 系统自动扫描处于冷却或半额状态的正常账号，将其当日可用点数恢复至每日上限（4 点）并转为满额状态

### Requirement: Proxy Binding and Fault Cooldown
系统 SHALL 支持为每个账号绑定出海代理节点，并在账号遭遇风控、请求失败或生成异常时进入冷却隔离期，避免对同一账号频繁重试。

#### Scenario: Request failure triggers cooldown
- **WHEN** 某个账号在生成过程中返回风控或异常报错
- **THEN** 系统将该账号标记为风控/异常，设置不少于 30 分钟的冷却退避窗口，调度器在该窗口期内跳过该账号
