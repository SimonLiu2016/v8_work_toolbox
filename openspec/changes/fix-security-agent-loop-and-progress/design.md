## Context

现有的 `SecurityAgentService` 和 `SecurityAgentView` 是通过 `AgentLoop` 驱动的 ReAct 循环。
在实际执行例如 Web 一键渗透（`91porn.com`）时，由于：
1. 默认 `maxIterations` 只有 3，且 UI 显示 `步骤 ${steps.length}/9`；
2. 工具调用期间没有在 UI 暴露正在进行的临时状态；
3. `AgentLoopResult.text`（大模型最终输出的渗透结论）未被存储和展示。

导致用户以为应用卡死在第 1 步。

## Goals / Non-Goals

**Goals:**
- 将 `SecurityAgentService.run` 的 `maxIterations` 提升至 8，并在预设任务 Prompt 中明确多步自主推进。
- 在 `SecurityAgentService` 增加 `currentToolRunning` 字段与流，由 `AgentLoop.onToolCallStart` 驱动，让 UI 实时显示「正在执行: xxx...」。
- 记录 `finalReport`，在 UI 上提供专门的「Agent 综合分析与渗透建议」卡片。
- 重构进度条文案，如 `已完成 2 步 · 运行中…`，并在工具执行时显示当前工具名称。

**Non-Goals:**
- 不改变底层各个 CLI 工具的调用实现（如 subfinder, httpx 的网络请求保持原状）。

## Decisions

### 1. 进度显示模型重构
- 弃用假步骤分母 `/9`：
  - 运行中且有活动工具时：显示 `步骤 ${steps.length + 1} · 正在执行 ${currentRunningTool}…`
  - 运行中且在模型思考时：显示 `步骤 ${steps.length + 1} · 模型思考中…`
  - 结束时：显示 `共完成 ${steps.length} 个步骤 · 已完成`
- 理由：清晰呈现 Agent 当前真实的生命周期，杜绝“卡在 1/9”的误解。

### 2. 捕获并渲染最终报告
- 在 `SecurityAgentService` 中增加 `String? finalReport`，在 `AgentLoop.run` 返回后保存 `result.text`。
- 在 `SecurityAgentView` 中，如果 `finalReport` 不为空，以卡片形式展示 Markdown/纯文本分析建议，并支持一键复制。

## Risks / Trade-offs

- **[Risk]** 增加 `maxIterations` 到 8 可能会增加 LLM API 的 token 消耗。
  - **Mitigation**: `SecurityAgentExecutor` 每个工具的回灌输出已经硬性截断在 500 字符以内，8 轮迭代的总 token 始终在 4k 范围以内，极为安全经济。
