## 1. 基础框架与工具注册

- [x] 1.1 在 `lib/tools/tool_definition.dart` 中新增 `ToolCategory.security`（'安全工具', Icons.security_outlined）
- [x] 1.2 创建 `lib/tools/security_toolbox/` 目录结构（ui / services / models 三层）
- [x] 1.3 创建 `SecurityToolboxDefinition`，在 `lib/tools/registry.dart` 注册
- [x] 1.4 创建 `SecurityToolboxMainPage`（仿 `OpsToolMainPage`，左侧导航 + Tab 内容区 + 右侧 AI 面板）
- [x] 1.5 左侧导航实现：会话 / 侦察 / 漏洞 / 利用 / 情报 / 脚本 / 报告 7 个 Tab 入口

## 2. 工具依赖管理器

- [x] 2.1 定义受管工具清单（`SecurityToolRegistry`），包含 nmap / arp-scan / masscan / nuclei / subfinder / httpx / katana / ffuf / sqlmap / gau / metasploit / bettercap / netexec / searchsploit 共 14 个工具
- [x] 2.2 实现 `ToolStatusChecker`：并行执行 `which` + 版本命令，5 秒超时，返回三态状态
- [x] 2.3 实现 Homebrew 检测（`which brew`）和工具安装服务（`brew install`，流式日志）
- [x] 2.4 实现 nuclei 模板管理：检测本地模板目录、触发 `-update-templates`、展示模板数量
- [x] 2.5 实现工具状态面板 UI（底部状态栏摘要 + 可展开详情面板，每个工具显示状态徽章和操作按钮）

## 3. 渗透会话系统（数据库）

- [x] 3.1 在 drift 数据库中新增迁移版本，创建 `pentest_sessions` / `pentest_assets` / `pentest_findings` / `timeline_events` / `threat_intel_cache` / `report_versions` 6 张表
- [x] 3.2 实现 `SessionRepository`：创建/读取/更新/删除会话，查询资产列表和 Finding 列表
- [x] 3.3 实现 `AssetRepository`：upsert 资产（去重逻辑），批量写入，订阅资产变更流
- [x] 3.4 实现 `FindingRepository`：写入 Finding、更新状态、按严重等级查询，订阅变更流
- [x] 3.5 实现 `TimelineRepository`：追加事件、按会话 ID 查询时间线（倒序）
- [x] 3.6 实现会话选择 UI：创建 LAN/Web 会话对话框、历史会话列表、当前会话切换

## 4. LAN 侦察模块

- [x] 4.1 实现 `NetworkInterfaceDetector`：解析 `ifconfig` 输出，提取活跃接口和 CIDR
- [x] 4.2 实现 `ArpScanService`：执行 `nmap -sn -PR` 或 `arp-scan -l`，解析 XML/文本输出，提取 IP/MAC/Vendor
- [x] 4.3 实现 `NmapService`：支持快速/标准/全端口三种模式，`-oX -` XML 流式输出，用 xml 包解析成结构化数据
- [x] 4.4 将 nmap 扫描结果写入 `PentestAsset`（含端口列表 JSON），触发时间线事件
- [x] 4.5 实现 LAN 侦察 UI：接口选择 + 扫描配置 + 实时进度 + 设备列表（IP/MAC/OS/服务摘要）
- [x] 4.6 实现网络拓扑图（`CustomPainter`）：星形布局，路由器中心，设备节点颜色编码风险，点击展示详情侧边栏

## 5. Web 资产侦察模块

- [x] 5.1 实现 `SubfinderService`：执行 subfinder，解析 JSON 输出，写入资产库
- [x] 5.2 实现 `HttpxService`：执行 httpx `-json -tech-detect -title -status-code`，解析输出，更新资产 metadata
- [x] 5.3 实现 `GauService`：执行 gau，解析 URL 列表，过滤并存储至会话
- [x] 5.4 实现 `FfufService`：执行 ffuf `-json`，解析发现路径，写入资产 URL 列表
- [x] 5.5 实现 `KatanaService`：执行 katana `-jc -json`，提取爬虫发现的 URL 和 JS 端点
- [x] 5.6 实现 Web 侦察 UI：域名输入 + 工具选择 + 阶段进度（发现→探测→爬虫）+ 资产列表（可按 status/tech 过滤）
- [x] 5.7 实现 Shodan API Key 配置（存入 `flutter_secure_storage`）和 shodan CLI 查询服务

## 6. 漏洞扫描模块

- [x] 6.1 实现 `NucleiService`：执行 `nuclei -json`，JSONL 逐行解析，每条发现实时写入 Finding；支持模板分类选择
- [x] 6.2 实现 `SqlmapService`：执行 sqlmap `--batch --output-dir`，扫描完后解析 JSON 结果文件
- [x] 6.3 实现 CVE CVSS 补充查询：从 nuclei 模板 metadata 优先读取；fallback 到 NVD API（`https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=`）
- [x] 6.4 实现漏洞扫描 UI：目标选择（从资产库）+ 模板分类勾选 + 实时 Finding 列表 + CVSS 统计卡片
- [x] 6.5 实现 AI 漏洞分析触发：扫描完成后自动将 Finding JSON 喂给 AI，结果展示在右侧 AI 面板

## 7. 漏洞利用模块

- [x] 7.1 实现 `MsfRpcService`：HTTP JSON-RPC 客户端，支持 auth/login、module.search、module.execute、session.list；包含连接状态检测和自动重试
- [x] 7.2 实现 msfrpcd 启动辅助：检测是否运行，未运行时通过 `Process.run` 启动本地 msfrpcd
- [x] 7.3 实现 `ExploitRecommendationService`：将 Finding 发送给 AI，AI 返回推荐的 MSF 模块名 + 参数，解析为结构化推荐对象
- [x] 7.4 实现利用执行 UI：AI 推荐卡片（模块名 + 参数预填充 + 确认按钮）+ 执行日志流 + 会话建立通知
- [x] 7.5 实现 `SearchsploitService`：调用 `searchsploit` CLI，解析结果，展示 PoC 脚本列表；支持按 CVE 搜索
- [x] 7.6 实现 PoC 脚本库 UI：脚本列表（分类/语言/CVE 筛选）+ 脚本详情预览 + 导入自定义脚本
- [x] 7.7 实现全局利用参数配置（LHOST/LPORT 设置，存入 settings_store）

## 8. 威胁情报模块

- [x] 8.1 实现 `NvdFeedService`：定时（4 小时）调用 NVD API，增量同步 CVE 数据写入 `threat_intel_cache`
- [x] 8.2 实现 CISA KEV 同步：定时从 `https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json` 拉取，标记 `is_kev = 1`
- [x] 8.3 实现 `GithubPocMonitorService`：通过 GitHub Search API 搜索新 CVE PoC 仓库，记录 PoC URL 至对应 CVE 记录
- [x] 8.4 实现资产交叉比对：新 CVE 同步后，与当前会话资产 metadata 中的服务版本比对，命中时自动创建 Finding
- [x] 8.5 实现 AI 日报生成：定时任务（cron 包，09:00 触发）聚合 24h 新漏洞，调用 AiService 生成中文摘要，存入本地
- [x] 8.6 实现威胁情报 UI：CVE 列表（CVSS/KEV/PoC 多维过滤）+ 关键词搜索 + 日报展示 + 资产命中高亮

## 9. 脚本生成模块

- [x] 9.1 实现 `ScriptGeneratorService`：封装 AI 调用，将用户自然语言描述转化为系统 prompt（附目标上下文），返回脚本内容
- [x] 9.2 实现脚本模板库（JSON 文件存储）：内置 10+ 模板（端口扫描 / 反弹 Shell / 爆破框架 / SMB 枚举 / HTTP 枚举 / Payload 生成），支持保存 AI 生成结果为模板
- [x] 9.3 实现脚本编辑器 UI：基于 `flutter_highlight` 实现 Python/Bash/Ruby 语法高亮的只读预览 + 可编辑区域
- [x] 9.4 实现沙箱执行服务：`Process.start` 执行脚本，stdout/stderr 流式展示，支持停止（SIGTERM），执行完成后提供"保存到会话"按钮

## 10. 报告生成模块

- [x] 10.1 实现 `ReportDataAggregator`：从指定会话聚合全部报告素材（资产列表、Finding、时间线、AI 分析记录）
- [x] 10.2 实现 AI 报告生成：将聚合素材发送给 AI，AI 生成执行摘要 + 技术叙述 + 修复建议（分段调用，每段 < 4000 tokens）
- [x] 10.3 实现 Markdown 报告格式化：标准报告结构（封面信息 / 执行摘要 / 资产清单表格 / Finding 详情 / 修复建议）
- [x] 10.4 实现 PDF 导出（复用现有 `pdf` 库）：封面页 + 目录 + 正文，Finding 以表格呈现，导出到用户选择目录
- [x] 10.5 实现报告版本管理：保存至 `report_versions` 表，版本列表 UI，历史版本预览

## 11. Security Agent 模式

- [x] 11.1 定义 Security Agent 工具集（`AgentTool` 列表）：run_nmap / run_nuclei / run_subfinder / run_httpx / run_ffuf / run_sqlmap / run_msf_module / query_intel / get_findings 9 个工具
- [x] 11.2 实现 `SecurityAgentService`：基于 `AgentLoop`，注入安全专家系统 prompt（附当前会话状态），管理工具执行回调
- [x] 11.3 实现高影响操作审批机制：`Completer` 暂停 Agent，弹出审批对话框，用户确认/跳过后恢复执行
- [x] 11.4 实现 Agent UI：自然语言输入框 + 启动/暂停/重置按钮 + 步骤进度指示器 + Agent 思考日志滚动展示
- [x] 11.5 实现 LAN 一键渗透预设工作流（快捷按钮，自动构建 Agent 任务描述）
- [x] 11.6 实现 Web 一键侦察预设工作流（快捷按钮，自动构建 Agent 任务描述）

## 12. 全局 AI 分析面板

- [x] 12.1 实现右侧常驻 AI 面板（与 OpsToolMainPage 同层级，宽度可折叠）
- [x] 12.2 实现安全专家系统 prompt 管理（加载当前会话摘要作为上下文）
- [x] 12.3 实现手动 AI 询问：用户可随时在 AI 面板输入问题，AI 带当前会话上下文回答
- [x] 12.4 实现自动分析推送：各模块完成扫描后自动触发 AI 分析，结果以气泡形式推送到 AI 面板

## 13. 系统权限与集成

- [x] 13.1 检查并更新 macOS entitlements：确保 nmap/masscan 等工具可以在沙盒外执行（`com.apple.security.temporary-exception.sbpl` 或移除沙盒限制）
- [x] 13.2 确认 Process 执行路径：Homebrew 工具安装在 `/opt/homebrew/bin`（Apple Silicon）或 `/usr/local/bin`（Intel），执行时设置正确的 PATH 环境变量
- [x] 13.3 测试全工具链端到端：安装 → 检测 → 执行 → 输出解析 → UI 展示，覆盖 LAN 和 Web 两个场景（真实 nmap 冒烟在 `test/security_toolchain_e2e_test.dart`，127.0.0.1 免特权；Web 侧各解析器由 `test/security_parsing_test.dart` 钉住。UI 展示需人工过一遍）
