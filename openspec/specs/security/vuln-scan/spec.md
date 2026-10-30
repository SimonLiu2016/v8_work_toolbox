# security/vuln-scan Specification

## Purpose
对侦察阶段发现的资产执行系统化漏洞扫描，整合 nuclei 模板引擎（覆盖 CVE、配置错误、弱凭证等），并通过 AI 对扫描结果进行优先级排序、风险解读和攻击路径分析。
## Requirements
### Requirement: Nuclei 模板扫描

系统 SHALL 使用 nuclei 对目标资产执行模板化漏洞扫描，支持按模板分类选择：`cves/`（CVE 漏洞）、`exposures/`（信息泄露）、`misconfiguration/`（配置错误）、`default-logins/`（默认凭证）、`network/`（网络层漏洞）、`technologies/`（技术识别）。

#### Scenario: Web 资产扫描

- **WHEN** 用户对存活 Web 资产列表启动 nuclei 扫描
- **THEN** 系统 SHALL 执行 `nuclei -l targets.txt -json` 并实时解析输出，每个发现立即写入 Finding 列表

#### Scenario: LAN 服务扫描

- **WHEN** 用户对 LAN 发现的服务（如 SMB、FTP、SSH）启动 nuclei 扫描
- **THEN** 系统 SHALL 使用 `network/` 和 `misconfiguration/` 分类模板，检测 SMB 签名缺失、匿名 FTP、SSH 弱密钥等问题

### Requirement: SQL 注入检测

系统 SHALL 集成 `sqlmap`，对爬虫或目录扫描发现的含参数 URL 执行自动化 SQL 注入检测，支持 GET/POST 参数，生成结构化发现报告。

#### Scenario: 批量注入检测

- **WHEN** 用户从 URL 列表中选择含参数的 URL 并启动 sqlmap
- **THEN** 系统 SHALL 以 `--batch --output-dir` 模式运行 sqlmap，将注入点发现解析为 Finding 条目

### Requirement: AI 漏洞优先级分析

系统 SHALL 在每次扫描完成后，将结构化 Finding 列表（JSON）发送给 AI 模型进行分析，AI SHALL 输出：前 5 高优先级漏洞的攻击价值说明、漏洞间可能的组合利用路径、最具可利用性的目标排序。

#### Scenario: 扫描后 AI 分析触发

- **WHEN** nuclei 扫描完成且发现 10+ 个 Finding
- **THEN** 系统 SHALL 自动触发 AI 分析，在右侧 AI 面板展示分析结论（不阻塞用户操作）

#### Scenario: AI 攻击路径推断

- **WHEN** AI 分析时发现某目标同时有 RCE 漏洞和信息泄露
- **THEN** AI SHALL 在分析中说明"可先利用信息泄露获取凭证，再利用 RCE 执行命令"的组合路径

### Requirement: CVSS 评分与风险分级

系统 SHALL 为每个 Finding 展示 CVSS 3.x 评分（从 nuclei 模板元数据或 NVD API 获取），并按 Critical(9-10) / High(7-8.9) / Medium(4-7) / Low(0-3.9) 分级展示，支持按严重等级过滤。

#### Scenario: CVSS 评分展示

- **WHEN** nuclei 发现一个 CVE-2024-xxxx 的漏洞
- **THEN** 系统 SHALL 展示该 CVE 的 CVSS 评分（优先从模板元数据读取，回退到 NVD API 查询）

### Requirement: 扫描进度与中断

系统 SHALL 实时展示扫描进度（已完成模板数/总模板数），支持随时暂停扫描，已发现的 Finding 在暂停后仍保留。

#### Scenario: 用户中断扫描

- **WHEN** 用户点击"停止扫描"
- **THEN** 系统 SHALL 终止 nuclei 进程，保留已写入的所有 Finding，状态标记为"已中断"

