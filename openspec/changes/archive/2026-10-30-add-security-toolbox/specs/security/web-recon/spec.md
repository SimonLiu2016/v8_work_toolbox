## Purpose

针对公网 Web 资产执行系统化的侦察：从单个根域名出发，通过被动情报、主动探测、内容发现三个阶段，构建目标的完整资产地图（子域名、IP、技术栈、URL 列表），为后续漏洞扫描提供高质量输入。

## ADDED Requirements

### Requirement: 子域名枚举

系统 SHALL 使用 `subfinder`（被动）和可选的 `amass`（主动/被动混合）枚举目标根域名的子域名，支持同时输入多个根域名，结果去重合并。

#### Scenario: 被动子域名发现

- **WHEN** 用户输入 `example.com` 并点击"开始侦察"
- **THEN** 系统 SHALL 调用 subfinder，通过多个被动数据源（Shodan、VirusTotal、crtsh 等）发现子域名，结果实时流式展示

#### Scenario: 多域名并行枚举

- **WHEN** 用户输入 3 个根域名
- **THEN** 系统 SHALL 并行枚举，最终合并去重后输出统一列表

### Requirement: HTTP 存活探测与指纹

系统 SHALL 使用 `httpx` 对所有发现的子域名进行 HTTP/HTTPS 存活探测，收集：HTTP 状态码、标题（title）、Web 技术栈（通过 `-tech-detect`）、服务器 header、内容长度、响应时间。

#### Scenario: 大批量并行探测

- **WHEN** 子域名列表包含 500+ 条目
- **THEN** 系统 SHALL 以并发方式探测，在 5 分钟内完成，展示存活比例统计

#### Scenario: 技术栈识别

- **WHEN** httpx 检测到某目标返回 `X-Powered-By: Express`
- **THEN** 系统 SHALL 将"Node.js/Express"记录至该资产的技术栈字段

### Requirement: 历史资产发现

系统 SHALL 调用 `gau`（Get All URLs）从 Wayback Machine、Common Crawl、URLScan 等历史数据源获取目标的历史 URL，过滤出潜在有价值的端点（API 路径、管理后台、备份文件）。

#### Scenario: 历史 URL 获取

- **WHEN** 用户对某存活资产点击"历史资产"
- **THEN** 系统 SHALL 返回按路径分组的历史 URL 列表，标注最后出现时间

### Requirement: Web 内容发现（目录爆破）

系统 SHALL 使用 `ffuf` 对存活 Web 资产执行目录与文件爆破，内置常用字典（SecLists 子集），支持扩展名猜测（.php/.asp/.bak/.conf 等），过滤无效响应。

#### Scenario: 目录爆破

- **WHEN** 用户对某 Web 资产启动"内容发现"
- **THEN** 系统 SHALL 使用内置字典执行 ffuf 扫描，发现的有效路径（非 404）实时展示

### Requirement: JS 感知爬虫

系统 SHALL 使用 `katana` 爬取存活 Web 资产，katana 支持解析 JavaScript 中的动态 URL（`-jc` 参数），提取 API 端点、表单 action、链接，作为后续漏洞扫描的输入。

#### Scenario: JS 端点提取

- **WHEN** katana 爬取某 SPA 应用时发现 `app.bundle.js`
- **THEN** 系统 SHALL 解析 JS 文件，提取其中的 API 路径（如 `/api/v1/users`）写入 URL 列表

### Requirement: 外部情报聚合（Shodan/Censys）

系统 SHALL 支持配置 Shodan API Key，通过 `shodan` CLI 或 `uncover` 工具查询目标 IP/组织的暴露服务，将情报结果（暴露端口、Banner、漏洞标签）合并至资产记录。

#### Scenario: Shodan 资产补充

- **WHEN** 用户对某子域名触发"外部情报查询"且 Shodan Key 已配置
- **THEN** 系统 SHALL 查询 Shodan 并将额外信息（CVEs、暴露的服务）追加至该资产记录
