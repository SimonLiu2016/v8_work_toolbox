## MODIFIED Requirements

### Requirement: Web 流水线自动触发弱口令探测
Web 全量评估流水线在 Katana 爬虫阶段完成后，SHALL 自动调用 `WebFormCredentialService` 对发现的候选登录 URL 执行弱口令探测；此阶段为流水线内置阶段，无需用户手动触发。

#### Scenario: Web 流水线自动触发弱口令探测
- **WHEN** 全量评估流水线完成 Katana 爬取阶段，爬取结果中含有登录页
- **THEN** 流水线自动进入弱口令探测阶段，调用 WebFormCredentialService，发现弱口令时写入 finding
