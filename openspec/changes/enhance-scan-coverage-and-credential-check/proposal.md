## Why

当前全量评估流水线存在三处明显的漏洞覆盖盲区：Web 扫描缺少默认凭据检测类别、Katana 爬取的含参数端点未自动接入 sqlmap 做注入探测、Hydra 服务层弱口令工具在 AgentExecutor 中仅为空存根未实现真实执行。这些缺口导致系统无法主动发现默认口令、SQL 注入以及服务层弱密码等高频高危漏洞，与工具箱"主动挖掘"的定位不符。

## What Changes

- **Web 流水线补全 Nuclei defaultLogins 类别**：在 `runWebPipeline` 的 Nuclei 扫描阶段补充 `NucleiCategory.defaultLogins`，覆盖已知开源系统的默认凭据漏洞模板（Tomcat、Spring Boot、若依、Grafana、Jenkins 等）
- **Katana 端点 → sqlmap 自动衔接**：在 Web 流水线 Katana 爬虫阶段结束后，自动筛选含查询参数的 URL（`?param=value`），批量交给 sqlmap 进行 SQL 注入探测，发现物实时写入 findings 数据库
- **Hydra AgentExecutor 实现**：在 `SecurityAgentExecutor` 中实现 `run_hydra` 工具的真实执行逻辑，支持对常见服务（SSH/FTP/HTTP-Basic）进行弱口令基线核查；结果写入 findings 库；LAN 流水线 nmap 阶段后若发现开放端口自动调度
- **扩充 Nuclei 扫描类别**：在 AI Agent 调度 `run_nuclei` 时，默认加入 `defaultLogins` + `exposures` 类别，覆盖更广的攻击面

## Capabilities

### New Capabilities

- `security/hydra-service-credential-check`：Hydra 服务层弱口令核查能力，支持 SSH/FTP/HTTP-Basic 等协议，结果写入 findings

### Modified Capabilities

- `security/adaptive-agent-pipeline`：Web 流水线自动衔接 sqlmap、补全 Nuclei 默认凭据扫描类别；LAN 流水线 nmap 后自动触发 Hydra 弱口令核查

## Impact

- `lib/tools/security_toolbox/services/security_pipeline_service.dart`：Web 流水线 Nuclei 调用补传 `defaultLogins`；Katana 后新增 sqlmap 自动衔接阶段；LAN 流水线新增 Hydra 触发阶段
- `lib/tools/security_toolbox/services/security_agent_executor.dart`：实现 `_runHydra()` 方法
- `lib/tools/security_toolbox/services/exploit_services.dart` 或新增 `hydra_service.dart`：封装 Hydra CLI 调用
- 无新增依赖
