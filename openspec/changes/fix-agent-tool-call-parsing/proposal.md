## Why

在“AI资讯与检索”或知识库问答中，当大语言模型（如具备原生 Function Calling / Tool Calling 微调的 DeepSeek、Qwen 等）决定调用工具时，常常输出 XML 标签风格的工具调用（例如 `<tool_call> { "name": "web_search", "arguments": ... } </tool_call>` 或未闭合标签），或者带有思考链 `<think>...</think>`。
然而，当前的 `AgentLoop.parseToolCall` 写死了仅匹配 Markdown 代码块 ````tool_call { ... } ````。解析器未命中后误判定为“模型给出普通回复”，从而直接将原始 `<tool_call> ...` 文本输出到前端界面，底层真实的工具检索完全未被执行。

## What Changes

1. **多格式高容错工具调用解析器**：
   - 增强 `AgentLoop.parseToolCall`，依次兼容匹配：
     - Markdown 代码块（````tool_call ... ```` 及 ````json ... ```` 带有 `"name"` 字段）；
     - XML 标签风格（`<tool_call> ... </tool_call>` 以及省略闭合标签的 `<tool_call> { ... }`）；
     - 裸 JSON 块（无标记包裹但包含合法 `"name"` 与 `"arguments"`/`"parameters"` 的顶层 JSON 对象）。
   - 增加思考链过滤：在解析前剥离 `<think>[\s\S]*?</think>` 块，避免思考过程中的文本干扰。
   - 参数字段归一化：将 `parameters` 与 `args` 统一归一化映射为 `arguments`。
2. **优化系统提示词引导**：
   - 在 `AiAssistantService` 与 `NotebookKbService` 的 System Prompt 中进一步明确工具调用输出格式规范，兼容各种微调倾向的模型。

## Capabilities

### New Capabilities
<!-- 无新增 capability -->

### Modified Capabilities
- `ai-news-assistant`: 增强智能体对话中的工具调用解析韧性，确保各类大模型采用 XML 或多样化语法输出工具调用时均能准确识别与执行，杜绝标签文本泄露至用户对话界面。

## Impact
- 影响代码：
  - `lib/services/agent_loop.dart`: 升级 `AgentLoop.parseToolCall` 正则与多分支解析逻辑。
  - `lib/tools/ai_assistant/services/ai_assistant_service.dart`: 优化系统提示词工具说明。
  - `test/agent_loop_test.dart`: 补充 XML 格式、缺闭合标签、think 标签、字段别名等多样化测试用例。
- 外部依赖与系统影响：无新依赖，完全向前兼容既有 Markdown 代码块格式。
