## 1. MCP Client Runtime & Configuration Enhancements

- [x] 1.1 Extend `McpClientConfig` in `lib/services/ai_config_store.dart` with args, env key-value pairs, timeoutSeconds, and preset helpers
- [x] 1.2 Implement `McpService` in `lib/services/mcp_service.dart` with stdio process spawning, JSON-RPC 2.0 handshake, tool enumeration, and tool execution
- [x] 1.3 Update `_showAddOrEditMcpDialog()` and MCP tab in `lib/shell/ai_config_page.dart` with env key-value editor, args list, preset button, and live "测试连接与探测工具" action
- [x] 1.4 Pre-populate and persist Firecrawl MCP server configuration according to `MCPtools.md` and verify handshake

## 2. AI Conversation & Web Data Retrieval Assistant

- [x] 2.1 Implement `AiAssistantService` in `lib/tools/ai_assistant/services/ai_assistant_service.dart` with message history, tool schema injection, and ReAct tool-calling execution loop
- [x] 2.2 Build `AiAssistantPage` in `lib/tools/ai_assistant/ui/ai_assistant_page.dart` featuring chat bubbles, real-time tool execution badges, Markdown formatting, and clickable source citations
- [x] 2.3 Register `AiAssistantToolDefinition` in `lib/tools/registry.dart` and add navigation entry in `ToolRegistry`

## 3. Scheduled News Retrieval & Background Notification

- [x] 3.1 Implement `ScheduledNewsService` in `lib/services/scheduled_news_service.dart` with task models, local JSON persistence, periodic timer scheduling, and briefing diff detection
- [x] 3.2 Implement macOS desktop notifications and in-app unread notification indicators
- [x] 3.3 Build scheduled tasks management sheet / drawer in `AiAssistantPage` for creating, toggling, and manually triggering intelligence tracking tasks

## 4. Verification & Testing

- [x] 4.1 Add unit tests in `test/mcp_assistant_test.dart` validating MCP serialization, JSON-RPC protocol framing, tool-calling agent flow, and news diff tracking
- [x] 4.2 Run `flutter analyze` and `flutter test` to ensure zero warnings or errors
