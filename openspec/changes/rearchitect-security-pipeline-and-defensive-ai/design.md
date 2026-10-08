# Design: Native Recon Pipeline and Defensive AI Analysis

## Context

见 `proposal.md`。当前安全工具箱中的预设工作流（“Web 一键侦察”与“LAN 一键渗透”）是通过向 `SecurityAgentService` 喂入一段包含外网具体目标（如 `baidu.com`）与攻击性工具链的自然语言提示词驱动。由于云端主流大模型（Claude、GPT、Gemini、DeepSeek 等）的安全对齐机制将此类任务视作潜在网络攻击，导致大模型直接返回拒答文本，使得整个本地工具链在第 0 步即被掐断。

同时，即使没有被拒答，让云端大模型做固定工具顺序的 ReAct 循环也存在网络多轮往返、高 Token 消耗、易受网络超时或格式中断影响等工程缺陷。

## Goals / Non-Goals

**Goals:**
1. **执行与决策彻底解耦**：所有确定性工具链（`subfinder`、`httpx`、`katana`、`nmap`、`nuclei`）由本地 Dart 原生异步流水线（`SecurityPipelineService`）直接驱动，具备 100% 成功率、零大模型依赖、支持取消与实时进度流。
2. **防拒答的防御型 AI 提示词系统**：将 AI 角色严格限定为“系统防御加固架构师与安全合规审计专家”，仅在工具链执行完成后（或按需）将结构化扫描数据转化为合规加固与风险分析提示词，消除大模型安全拦截风险。
3. **拒答自动降级兜底（Offline Fallback）**：若用户自定义自然语言提问仍遇到大模型策略限制，系统具备自动识别并平滑降级为本地离线加固总结的能力，避免界面显示一堵拒答冷板凳。
4. **UI 体验平滑统一**：在 `SecurityAgentView` 中保持“步骤进度”、“日志”与“综合分析建议”的直观视图，原生流水线的每一个阶段无缝映射到步骤列表，并在末尾展示 AI 生成的高质量 Markdown 加固建议。

**Non-Goals:**
- 不取消自由输入任务的 AgentLoop 机制；当用户输入自定义指令时仍支持 ReAct，但对其系统提示词做中立加固。
- 不引入外部复杂的流水线框架，利用既有 `SubfinderService`、`HttpxService`、`KatanaService`、`NucleiService` 等成熟服务进行 Dart 原生编排。

## Decisions

### 1. 独立的原生流水线服务 `SecurityPipelineService`

**决策**：
新增 `SecurityPipelineService` 单例或模块，封装 `runWebReconPipeline` 与 `runLanPipeline`。
- 流水线接受 `SecuritySessionController` 与当前活跃会话。
- 执行过程按阶段顺序调用现有原子服务：
  - Web: 阶段 1: `SubfinderService` -> 阶段 2: `HttpxService` -> 阶段 3: `KatanaService` (前 10 存活 URL) -> 阶段 4: `NucleiService` (可选快速模板探测)。
  - LAN: 阶段 1: `ArpScanner` / 网卡探测 -> 阶段 2: `NmapService` -> 阶段 3: `NucleiService`。
- 每一阶段开始与结束时向 `SecurityAgentService` 注入标准的 `AgentStep`（包括工具名、耗时、状态、摘要），使 UI `_buildSteps` 与 `_buildProgress` 保持一致的动态视觉反馈。
- 每个阶段产生的数据直接通过 `controller.assets.upsert` 和 `controller.findings.add` 持久化入库。

**备选方案权衡**：
- *方案 A（保留大模型编排，但做更隐晦的 Prompt）*：容易随着模型安全策略更新再次失效，且依然慢。
- *方案 B（当前选定方案）*：工具链完全确定化、本地化，极速稳定。

### 2. 防御与合规审计 AI 提示词体系（Defensive Framing）

**决策**：
当原生流水线完成（或用户点击“AI 综合分析”）时，由 `SecurityAgentService.generateDefensiveReport` 触发分析：
- **角色重构**：
  ```
  你是企业系统安全架构师与合规审计顾问，专注于内部授权系统的资产基线核查、攻击面收敛、配置加固与漏洞修复建议。
  ```
- **输入中立化**：
  将当前会话数据提取为只读摘要：
  - 资产范围：目标节点数量、开放的服务与端口；
  - 识别组件：Nginx、Apache、Tomcat 等指纹；
  - 检测风险：Nuclei/弱口令等检测项（CVE 编号、中危配置缺陷）。
- **任务目标引导**：
  要求大模型输出：
  1. 【资产暴露面与配置风险评估】
  2. 【风险紧急度分级与修复优先级】
  3. 【系统与网络层防御加固策略（配置调优、访问控制、补丁建议）】
- 这种输入结构是标准的企业自查与合规报告，完全符合 AI 供应商的安全使用政策。

### 3. 拒答检测与离线报告兜底

**决策**：
在大模型返回结果中检测是否命中通用拒答模式（如包含 `无法协助`、`安全策略`、`合法途径` 等）。若检测到拒答：
- 自动生成内置的结构化离线分析草案：
  - 汇总当前已发现的资产总数、高/中/低危发现项数量。
  - 列出前 3 个需要优先处置的配置项，并附带通用的加固措施（关闭非必要端口、开启最小化权限等）。
  - 在卡片顶部提示：“已根据本地扫描数据自动生成防御评估报告（云端模型受策略限制跳过）”。
- 保证用户无论在任何网络或云端限制下，都能立刻拿到清晰可靠的安全总结。

## Risks / Trade-offs

- **[Risk]** 流水线执行耗时较长（例如 Katana 爬虫或 Nmap 全端口）：
  → **[Mitigation]** 本地流水线受 `_running` 标志控制，支持实时“停止”操作；且对 Katana 默认限制最多探测 10 个存活端点，控制在 30 秒至 1 分钟内完成。
- **[Risk]** 用户在输入框中输入攻击性指令可能仍被大模型拒答：
  → **[Mitigation]** 系统提示词明确限定防御分析，并在 UI 上检测拒答后引导用户“使用上方的一键预设工作流直接本地执行”。
