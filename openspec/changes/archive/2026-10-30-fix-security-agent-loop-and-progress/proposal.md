## Why

用户在安全工具箱中新建 Web 目标会话并点击「启动 Agent」后，界面显示「步骤 1/9 · 已完成」后彻底停止，且思考日志无更新。
经排查主要存在四大缺陷：
1. **伪误导进度展示**：UI 将 9 个可用工具总数硬编码为步骤分母（`步骤 ${steps.length}/9`），导致只调用了一次工具后显示 `1/9 · 已完成`，让用户误以为还有 8 个步骤被卡死。
2. **迭代上限过低**：`SecurityAgentService.run` 默认 `maxIterations` 仅为 3，而完整的 Web/LAN 渗透往往需要 4~6 步以上，导致刚进行到子域名枚举就耗尽轮次退出。
3. **缺少实时运行态与耗时反馈**：底层工具（如 `subfinder`、`httpx`）需要数十秒网络探测，而在执行期间未触发流式进行中状态，日志区一片空白如同冻结。
4. **最终大模型回答丢失**：`AgentLoop` 收敛生成的最终分析与加固建议 `finalText` 未保存也未在 UI 渲染。

## What Changes

- **修正 Agent 步骤与进度展示**：
  - 移除硬编码的 `/9`，改为动态展示当前执行的工具轮次（例如 `轮次 1 · 正在运行 run_subfinder...`、`共完成 3 步 · 已完成`）。
  - 支持“正在执行”中的临时步骤实时反馈，在工具启动与完成之间提供清晰的加载态与工具名提示。
- **调整 Agent 迭代轮次与引导 Prompt**：
  - 将 `SecurityAgentService.run` 的默认 `maxIterations` 由 3 提升至 8，并优化一键预设 Prompt，指引大模型分阶段自主衔接（发现资产 -> 探测端口/端点 -> 扫描漏洞 -> 最终分析）。
- **持久化并展示 Agent 最终综合分析报告**：
  - 在 `SecurityAgentService` 中记录 `finalReport`，并在思考日志卡片下方增加「Agent 综合分析与渗透建议」展示区。

## Capabilities

### New Capabilities
- `security/agent-workflow`: Security Agent 自动化渗透决策循环、实时步骤状态反馈与综合分析报告展示。

### Modified Capabilities
<!-- 无已有 spec 变更 -->

## Impact

- `lib/tools/security_toolbox/services/security_agent_service.dart`：支持当前执行中步骤状态流、保存 finalReport、调整默认 maxIterations 至 8。
- `lib/tools/security_toolbox/ui/security_agent_view.dart`：重构进度条文案与正在执行提示，增加最终分析报告卡片。
