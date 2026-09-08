## Why

Users need to connect external Model Context Protocol (MCP) tools—specifically the Firecrawl crawler and search MCP (`firecrawl-mcp`)—into V8WorkToolbox to give the application live web crawling, search, and deep research capabilities. Although `ai_config.json` had a placeholder `McpClientConfig` schema, the app previously lacked an active MCP execution runtime engine, had an incomplete configuration dialog that could not configure environment variables or arguments, and lacked an interactive chat interface and scheduled retrieval notification capability.

This change introduces a native MCP runtime engine, completes the external MCP configuration workflow with connection testing, adds an interactive AI Assistant for chat and web data retrieval via tool calling, and provides scheduled retrieval tasks to periodically monitor and notify users of fresh intelligence and news.

## What Changes

- **External MCP Configuration & Runtime Engine**:
  - Enhance `McpClientConfig` and the "外部 MCP 客户端" configuration interface to support command arguments (`args`), custom environment variables (`env` key-value pairs), and execution timeout.
  - Implement a native Dart `McpService` managing stdio subprocess lifecycles, JSON-RPC 2.0 protocol handshake (`initialize`, `notifications/initialized`), tool discovery (`tools/list`), and execution (`tools/call`).
  - Add an authentic "测试连接 / 探测工具" action in the MCP settings tab that tests process launch, JSON-RPC handshake, tool listing, and reports health status.
  - Pre-populate and support the Firecrawl MCP configuration according to `MCPtools.md` (`npx -y firecrawl-mcp`, `FIRECRAWL_API_URL`, `FIRECRAWL_API_KEY`).
- **AI Conversation & Web Data Retrieval Assistant**:
  - Create a new tool page / modal `AiAssistantPage` ("AI 资讯与检索助手") registered in `ToolRegistry` and accessible via ActivityBar or top bar.
  - Implement an agentic Tool-Calling loop in `AiAssistantService` integrating registered MCP tools (e.g. `firecrawl_search`, `firecrawl_scrape`) with configured LLM slots.
  - Render rich conversation messages with real-time tool execution badges, Markdown content, and source citations.
- **Scheduled Information Retrieval & Notifications**:
  - Implement `ScheduledNewsService` to manage periodic search tasks with customizable intervals, search queries, and prompt goals.
  - Perform background automated retrievals, generate incremental briefings, and compare digests to prevent repetitive alerts.
  - Provide in-app badges, notification banners, and desktop system notifications when fresh intelligence is detected.

## Capabilities

### New Capabilities
- `ai-news-assistant`: Covers the interactive AI chat dialog, web retrieval agent loop with MCP tool calling, and background scheduled news monitoring with desktop notifications.

### Modified Capabilities
- `ai-configuration`: Updates the external MCP client requirements to specify environment variable injection, arguments array configuration, two-way connection and tool enumeration verification, and active runtime process management.

## Impact

- **Services**:
  - New `lib/services/mcp_service.dart` for process-level MCP JSON-RPC 2.0 client.
  - New `lib/services/scheduled_news_service.dart` for background periodic queries and notifications.
  - Updates to `lib/services/ai_config_store.dart` for enhanced MCP configuration fields and persistence.
- **UI & Tools**:
  - Updates to `lib/shell/ai_config_page.dart` with environment variable editor, args field, and test connection button.
  - New `lib/tools/ai_assistant/` tool module (`ai_assistant_page.dart`, `models/`, `services/`, `widgets/`).
  - New tool registration in `lib/tools/registry.dart`.
- **Dependencies**: Uses native Dart `dart:io` `Process` and standard JSON-RPC over stdio; no heavy external binary dependencies.
