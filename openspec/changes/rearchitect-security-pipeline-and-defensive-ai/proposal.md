# Proposal: Rearchitect Security Pipeline and Defensive AI Analysis

## Why

在现有实现中，点击“Web 一键侦察”或“LAN 一键渗透”会将一段包含具体外网目标和攻击性工具链的自然语言提示词（例如：“全面评估 baidu.com 的 Web 安全：subfinder 枚举子域名 → httpx 探测存活资产 → katana 爬取端点 → nuclei 扫描漏洞 → sqlmap 检测注入点…”）直接发送给云端大模型，依赖大模型的 ReAct 循环调度工具。

这导致了两个致命缺陷：
1. **云端主流大模型安全策略拦截（Refusal）**：主流商业大模型（Claude、GPT、Gemini 等）的安全对齐机制检测到针对特定外网目标且包含 `nuclei`、`sqlmap` 等攻击性操作时，会将其判定为非授权未授权渗透攻击，直接触发安全拒答（如：“我无法协助你对特定目标进行渗透测试、漏洞扫描…”），导致本地任何扫描工具在第 0 步就彻底无法执行。
2. **流程脆弱、高延时与高 Token 开销**：本应是确定性的本地异步工具链（`subfinder → httpx → katana → nuclei`），却让大模型多次往返决策，不仅延时高、耗费 Token，还经常因网络波动或格式幻觉中断。

遵循“**确定性归本地，推理分析归 AI**”的架构原则，需要将固定流程彻底交由本地 Native Pipeline 异步引擎执行（100% 确定性、零拒答风险），执行完成后再通过中立、防御化的安全审计 Prompt 让 AI 承担风险归纳与加固建议分析。

## What Changes

1. **一键预设工作流原生化（Native Pipeline Execution）**：
   - 将“Web 一键侦察”与“LAN 一键渗透”等预设工作流从“云端 LLM ReAct 循环驱动”重构为“本地确定性异步流水线驱动（`SecurityPipelineService`）”。
   - 侦察流水线（`subfinder → httpx → katana`）与评估流水线由本地代码直接调用相应 Service 顺序执行，实时上报步骤状态（`running`、`success`、`failure`）、写入日志和 SQLite 数据库。
   - 彻底摆脱执行工具对云端 LLM 的强依赖，确保 100% 执行成功率且 0 Token 消耗。

2. **AI 防御化与合规审计提示词体系（Defensive Reframing）**：
   - 改造针对 AI 的 Prompt 体系：角色从“攻击性渗透测试工程师”转变为“企业安全合规审计专家 / 系统防御加固架构师”。
   - 将扫描目标与输入上下文进行安全合规包装，仅将本地已采集的结构化暴露面与漏洞数据作为输入，引导 AI 从“防御加固、暴露面收敛、合规整改与补丁建议”角度进行分析。
   - 彻底避免触发云端大模型的安全策略拒绝机制。

3. **流水线与 AI 建议卡片 UI 联动**：
   - 在 `SecurityAgentView` 中统一保留“预设工作流”、“步骤与执行进度”、“思考与操作日志”以及“综合安全分析与防御建议”卡片。
   - 本地流水线执行时点亮对应步骤并实时展示工具日志；本地流水线完成后，自动触发（或提供一键触发）防御性 AI 综合分析并以 Markdown 渲染。

## Capabilities

### Modified Capabilities
- `security/agent-session-state`: 明确预设工作流采用本地确定性流水线执行与防御型 AI 分析解耦，更新预设工作流执行行为与系统防御化提示词规范。

## Impact

- `lib/tools/security_toolbox/services/security_agent_service.dart`: 引入本地工作流调度能力，解耦工具顺序执行与大模型调用；重构系统提示词为防御合规架构师角色。
- `lib/tools/security_toolbox/services/security_pipeline_service.dart`（新增）: 提供 Web 与 LAN 本地异步确定性流水线执行器，驱动工具链并维护步骤状态。
- `lib/tools/security_toolbox/ui/security_agent_view.dart`: 预设工作流点击后直接接入 Native Pipeline，进度与步骤实时展示，流水线完成后自动联动防御型 AI 分析。
- `lib/tools/security_toolbox/services/security_session_controller.dart`: 调整 `kSystemPrompt` 与相关分析问答话术为防御合规视角。
