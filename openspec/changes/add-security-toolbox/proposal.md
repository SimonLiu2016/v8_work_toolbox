## Why

作为安全工程师，日常的渗透测试工作需要在多个独立工具之间频繁切换，缺乏统一的会话管理和 AI 分析层，导致大量时间浪费在工具调用、结果整理和报告撰写上。当前 V8WorkToolbox 已具备 AI Agent Loop、MCP 协议、PDF 导出等基础能力，具备承载专业级安全工具箱的技术条件。

## What Changes

- **新增** `security` 工具分类（`ToolCategory.security`），在活动栏独立呈现
- **新增** 安全工具箱主模块（仿 `ops_tool` 多 Tab 架构），含 6 个子工具 Tab
- **新增** 工具依赖管理器：自动检测/安装 Homebrew 工具链（nmap、nuclei、metasploit 等）
- **新增** 渗透会话系统：统一管理目标、资产、漏洞发现、执行历史、AI 分析
- **新增** LAN 侦察工作流：一键扫描局域网，设备发现 → 服务枚举 → 漏洞识别
- **新增** Web 资产侦察工作流：域名输入 → 子域名发现 → 存活探测 → 漏洞扫描
- **新增** 漏洞利用模块：Metasploit RPC 集成，AI 自动选模块
- **新增** 威胁情报 Feed：NVD/CISA/GitHub 实时漏洞追踪，AI 日报摘要
- **新增** 脚本生成器：AI 生成定制化渗透脚本，沙箱执行
- **新增** 渗透报告生成器：自动聚合会话数据，AI 生成专业报告，导出 PDF/Markdown
- **新增** Security Agent 模式：AI 通过 AgentLoop 全自动驱动渗透工作流

## Capabilities

### New Capabilities

- `security/tool-dependency-manager`: 工具链依赖检测、Homebrew 安装、版本管理、状态监控
- `security/session-manager`: 渗透会话的创建、持久化、资产管理、发现物追踪、会话时间线
- `security/lan-recon`: 局域网侦察工作流（ARP 发现、nmap 扫描、OS/服务指纹、可视化拓扑）
- `security/web-recon`: 公网 Web 资产侦察（子域名枚举、HTTP 探测、内容发现、技术栈识别）
- `security/vuln-scan`: 漏洞扫描（nuclei 模板扫描、CVE 匹配、CVSS 评级、AI 优先级分析）
- `security/exploit-manager`: 漏洞利用（Metasploit RPC、exploit 库管理、AI 辅助选模块）
- `security/threat-intel`: 威胁情报 Feed（NVD/CISA/GitHub PoC 追踪、AI 摘要、资产交叉比对）
- `security/script-generator`: AI 驱动的渗透脚本生成、模板库管理、沙箱执行
- `security/pentest-report`: 自动化报告生成（时间线聚合、AI 叙事撰写、PDF/Markdown 导出）
- `security/ai-agent`: Security Agent 模式（AI 通过 AgentLoop 驱动整个渗透工作流）

### Modified Capabilities

（无，纯新增功能，不改变现有模块行为）

## Impact

- **新增工具分类**：`lib/tools/tool_definition.dart` 增加 `ToolCategory.security`
- **新增工具模块目录**：`lib/tools/security_toolbox/`（ui/services/models 三层架构）
- **新增工具注册**：`lib/tools/registry.dart` 注册 `SecurityToolboxDefinition`
- **新增数据库表**：drift 迁移，新增 pentest session 相关表
- **复用现有基础设施**：`AgentLoop`（Security Agent）、`AiService`（AI 分析）、`MCP`（工具暴露）、`pdf` 库（报告导出）、Notebook（情报归档）、ProxySettings（扫描流量路由）
- **新增系统级 Shell 权限**：nmap/metasploit 需要特权执行（macOS entitlements）
- **新增外部依赖**（Homebrew）：nmap、masscan、arp-scan、nuclei、subfinder、httpx、katana、ffuf、sqlmap、gau、metasploit、bettercap、netexec
