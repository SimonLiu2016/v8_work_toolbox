## MODIFIED Requirements

### Requirement: Web 流水线扫描类别完整覆盖
系统的 Web 全量评估流水线 SHALL 在 Nuclei 扫描阶段传入完整的漏洞类别集合，包含：cves（已知漏洞）、misconfiguration（配置缺陷）、exposures（信息泄露）、**defaultLogins（默认凭据）**；不得遗漏 defaultLogins 类别。

#### Scenario: Web 流水线 Nuclei 扫描类别完整
- **WHEN** 全量评估流水线对 Web 目标执行 Nuclei 扫描
- **THEN** Nuclei 进程参数中包含 `-tags cve,misconfig,exposure,default-login`，覆盖全部四个类别

### Requirement: Web 流水线 Katana 端点 → sqlmap 自动衔接
Web 全量评估流水线在 Katana 爬虫阶段完成后，SHALL 自动筛选含 URL 查询参数的端点（格式为 `?param=value`），批量交给 sqlmap 执行 SQL 注入探测，发现物实时写入 findings 数据库；此阶段无需人工触发。

#### Scenario: 含参数端点自动衔接 sqlmap
- **WHEN** Katana 爬取到 URL `https://example.com/article?id=1`（含查询参数）
- **THEN** 该 URL 在 Katana 阶段结束后自动加入 sqlmap 的扫描目标队列，若存在注入漏洞则以 `high` 严重度写入 finding

#### Scenario: 无含参数端点时跳过 sqlmap
- **WHEN** Katana 爬取结果中所有 URL 均无查询参数
- **THEN** sqlmap 阶段自动跳过，流水线继续后续阶段

### Requirement: LAN 流水线 nmap 后自动触发 Hydra 弱口令核查
LAN 全量评估流水线在 nmap 服务枚举阶段完成后，SHALL 自动对发现的开放常见服务端口（SSH:22、FTP:21）的主机执行 Hydra 弱口令基线核查，无需人工触发。

#### Scenario: 发现 SSH 端口自动触发 Hydra
- **WHEN** nmap 阶段发现主机 `192.168.1.100` 开放 22 端口（SSH 服务）
- **THEN** Hydra 弱口令核查自动对该主机 SSH 服务执行，若命中弱口令则写入 critical finding
