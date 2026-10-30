## Why

当前安全工具箱存在两个明显短板：一是 AI 返回的 Markdown 内容在弹窗中以纯文本显示，可读性差；二是所有功能仍需用户手动逐步触发（侦察→扫描→研判→报告），缺乏从"一键启动"到"最终报告"的自主闭环能力，与工具箱作为主动式安全评估平台的目标不符。

## What Changes

- **Markdown 格式化渲染**：将 `_AiRemediationDialog` 和 `_BatchRemediationDialog` 中的 `SelectableText` 替换为 `MarkdownBody`，AI 返回内容以富文本格式展示
- **Agent Executor 接入真实工具**：修复 `SecurityAgentExecutor`，使其工具调用真正驱动 `NmapService`、`NucleiService`、`SqlmapService` 等，并将结果写入数据库
- **自适应 AI 流水线**：新增 `AdaptiveAgentPipeline`，在固定侦察基础阶段完成后，引入 AI 研判层动态决定深度探测方向（最多 3 轮），最终生成综合评估报告
- **一键全量评估入口**：在 Agent 视图新增"一键全量评估"按钮，统一替代当前分散的手动触发按钮
- **分层防拒绝提示词框架**：强化 AI 系统提示，在合规授权声明、工具描述语言、任务框定三个层次全面规避内容安全拦截；拒答时自动降级至本地离线报告

## Capabilities

### New Capabilities

- `security/adaptive-agent-pipeline`: 自适应 AI 驱动流水线，固定基础阶段 + AI 研判层 + 动态深度探测 + 最终报告生成
- `security/markdown-rendering`: AI 响应内容在 UI 弹窗中的 Markdown 格式化渲染能力

### Modified Capabilities

- `security/agent-session-state`: AgentExecutor 从 dry-run 转为真实工具调用，工具结果写库并以摘要回灌 AI

## Impact

- `lib/tools/security_toolbox/services/security_agent_executor.dart`：重写工具执行回调
- `lib/tools/security_toolbox/services/security_pipeline_service.dart`：新增 `AdaptiveAgentPipeline`
- `lib/tools/security_toolbox/services/security_agent_service.dart`：强化 `_buildSystemPrompt` 分层防拒绝框架
- `lib/tools/security_toolbox/ui/vuln_scan_view.dart`：Markdown 渲染替换（2 处）
- `lib/tools/security_toolbox/ui/security_agent_view.dart`：新增一键全量评估按钮
- 依赖：`flutter_markdown`（已在 pubspec.yaml，无需新增）
