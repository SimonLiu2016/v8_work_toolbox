## Context

See `proposal.md` for motivation. Currently, `V8WorkToolbox` manages AI models and capability slots via `AiService` and `AiConfigStore`. `McpClientConfig` existed as a plain JSON data class in `AiConfigStore`, but the application lacked an actual process-level MCP runtime client, lacked fields for arguments and environment variables in the UI, and lacked conversational assistant features.

`firecrawl-mcp` is an external Node.js package providing 26 tools over standard MCP stdio protocol (`npx -y firecrawl-mcp`). It requires environment variables `FIRECRAWL_API_URL` and `FIRECRAWL_API_KEY`.

## Goals / Non-Goals

**Goals:**
- Provide a native Dart stdio-based MCP client (`McpService`) communicating via JSON-RPC 2.0 (handling `initialize`, `notifications/initialized`, `tools/list`, `tools/call`).
- Extend `McpClientConfig` and the "外部 MCP 客户端" configuration tab to support arguments, environment variables, and live connection/tool enumeration testing.
- Implement an interactive AI Assistant tool page (`AiAssistantPage`) registered in `ToolRegistry` and accessible from ActivityBar/navigation, supporting chat history, Markdown formatting, and automated tool calling with registered MCP tools.
- Implement `ScheduledNewsService` for periodic intelligence retrieval with persistent task storage, diff detection, and macOS in-app / desktop notifications.
- Pre-populate and verify the Firecrawl MCP configuration with connection testing and graceful error reporting (e.g. for remote 502 Bad Gateway).

**Non-Goals:**
- Building a full cloud-based crawler within the local Flutter app (we delegate crawling and extraction to the MCP server).
- Implementing complex multi-agent orchestration frameworks (we use a robust single-agent ReAct / function calling loop directly integrated with `AiService`).
- Modifying remote server infrastructure (handling remote Caddy/Docker 502 recovery is the user's infrastructure task; the client provides detection and actionable feedback).

## Decisions

### 1. Native Dart MCP Stdio Client Engine (`McpService`)
- **Decision**: Implement `McpService` using standard `dart:io` `Process.start` with pipes for `stdin` and `stdout`. Messages are JSON-RPC 2.0 delimited by newlines (`\n`) as per Model Context Protocol specification.
- **Alternatives Considered**:
  - *Calling an external Python or Node proxy*: Adds external runtime dependency and fragility.
  - *Third-party Dart MCP package*: Existing packages on pub.dev are either outdated, unmaintained, or require Flutter web/Wasm bindings incompatible with pure macOS desktop apps.
- **Protocol Details**:
  1. Spawns process with inherited system environment merged with custom `client.env`.
  2. Sends `initialize` request with client info `{"name": "V8WorkToolbox", "version": "0.1.0"}` and protocol `2024-11-05`.
  3. Sends `notifications/initialized`.
  4. Calls `tools/list` and caches available tools (`name`, `description`, `inputSchema`).
  5. Exposes `callTool(toolName, arguments)` with configurable timeout.

### 2. UI Configuration Enhancement in `ai_config_page.dart`
- **Decision**: Expand the MCP dialog to include:
  - Command (`npx`)
  - Arguments (`-y, firecrawl-mcp` as a chip/comma-separated input)
  - Environment variables (Key-Value dynamic list editor)
  - Quick-preset button: "一键填入 Firecrawl MCP 模板"
  - "测试连接与探测工具" action button that runs live testing and displays tool count and names.

### 3. AI Assistant & Agentic Tool-Calling Loop
- **Decision**: Build `AiAssistantService` that uses `AiService.instance.chat(slot: 'chat')` (or 'text'). The system prompt provides instructions and registered MCP tool schemas. When the model invokes a tool:
  1. Assistant catches the tool call intent.
  2. Invokes `McpService.instance.callTool(...)`.
  3. Returns the tool output as context to the LLM to formulate the final answer.
  4. Renders interactive status badges (`🔍 正在调用 firecrawl_search...`, `✓ 获取到 3 条数据`) and formatted citations.
- **UI Structure**:
  - Main panel: Message list with user & assistant bubbles, streaming state, copy button.
  - Sidebar / Drawer: Scheduled tasks list ("定时检索与资讯跟踪") and active MCP tools inspector.

### 4. Background Scheduling and Notifications (`ScheduledNewsService`)
- **Decision**: Use in-memory `Timer.periodic` checking due tasks every 60 seconds while the application runs.
  - Stores tasks in `~/.v8worktoolbox/scheduled_news_tasks.json`.
  - Stores briefing records in `~/.v8worktoolbox/scheduled_news_history.json`.
  - Compares the newly generated summary against the latest run's digest; if fresh items are found, sends a notification via macOS system notification (`osascript -e 'display notification ...'`) and sets an in-app unread badge.

## Risks / Trade-offs

- **[Risk] Remote Firecrawl backend 502 Bad Gateway** → The Caddy layer is up, but the remote Firecrawl container is currently unreachable.
  - *Mitigation*: The test connection and AI chat loop explicitly catch 502 errors and display clear diagnostics: `"MCP 进程握手成功，但远程 Firecrawl 服务返回 502 Bad Gateway，请检查 43-133-77-38.nip.io 的后端容器状态"`, while allowing other MCP tools or fallback search to proceed.
- **[Risk] Long running crawls hanging the UI** → Crawling or multi-page searches can take 10-30 seconds.
  - *Mitigation*: All MCP calls are asynchronous with a default 60s timeout, non-blocking UI spinners, and cancellation support.
- **[Risk] LLM hallucinating tool call formats** → Different models format tool calls differently.
  - *Mitigation*: Provide clear system prompt instructions with few-shot tool call examples and JSON schema validation.

## Open Questions

- *None affecting current architecture*: User can configure additional MCP servers (e.g. filesystem, sqlite, brave-search) in the future using the same unified `McpService`.
