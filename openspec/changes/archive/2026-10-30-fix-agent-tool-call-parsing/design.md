## Context

在智能体循环执行时，模型对于工具调用输出的语法具有多样性。尤其是微调过 Function Calling 机制的开源模型，常常自发输出 `<tool_call> { ... } </tool_call>` 或 `<tool_call> { ... }` 格式。当前 `AgentLoop.toolCallPattern` 仅支持 Markdown 代码块，导致未匹配的工具调用直接作为普通文本泄漏给用户。

## Goals / Non-Goals

**Goals:**
- 支持 XML 风格（`<tool_call>...</tool_call>` 与未闭合 `<tool_call>...`）及 Markdown 风格（````tool_call```` / ````json````）解析。
- 提取并规整参数字段别名（`arguments` / `parameters` / `args`）。
- 过滤 `<think>...</think>` 思考链干扰。
- 增加全面单元测试，覆盖常见 LLM 工具输出样式。

**Non-Goals:**
- 不强制改变模型原生的 Function Call 训练偏好，以高容错解析为主。

## Decisions

### 1. 多层级正则匹配与候选提取
- **决策**：在 `AgentLoop.parseToolCall` 中，首先剥离 `<think>...</think>` 思考内容，然后按优先级尝试匹配：
  1. ````tool_call\s*(\{[\s\S]*?\})\s*```` (标准 Markdown 代码块)
  2. `<tool_call>\s*(\{[\s\S]*?\})\s*(?:</tool_call>)?` (XML 标签，含缺省闭合标签)
  3. ````json\s*(\{\s*"name"[\s\S]*?\})\s*```` (标注 json 代码块)
  4. 裸 JSON 匹配（顶层包含 `"name"` 与 `"arguments"`/`"parameters"` 的独立 JSON 对象）。
- **理由**：能够无缝兼容市面上几乎所有模型，防止任何工具调用被误当作普通文本。

### 2. 参数字段归一化
- **决策**：解析成功后，检查 `data['arguments'] ?? data['parameters'] ?? data['args']`，统一包装为标准的 `arguments` 映射返回。

## Risks / Trade-offs

- **[Risk]** 普通包含 JSON 的技术讨论被误识别为工具调用。
  → **Mitigation**: 严格校验顶层必须包含已知或合法的 `"name"` 字符串字段，以及参数字典。若 JSON 非法或缺少核心字段，安全降级为普通文本。
