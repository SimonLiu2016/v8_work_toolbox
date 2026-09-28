## 1. 增强 AgentLoop 工具调用解析器

- [x] 1.1 改造 `AgentLoop.parseToolCall` 支持 XML 风格（`<tool_call>`）、Markdown json 代码块和裸 JSON
- [x] 1.2 支持 `<think>...</think>` 思考链过滤与参数字段别名（`parameters` / `args`）归一化
- [x] 1.3 优化 `AiAssistantService` 与 `NotebookKbService` 的系统提示词

## 2. 单元测试与端到端集成验证

- [x] 2.1 在 `test/agent_loop_test.dart` 补充 XML 标签、未闭合标签、think 块、参数别名测试
- [x] 2.2 重新编译 macOS Release 版本并安装重启，验证应用端实际对话
