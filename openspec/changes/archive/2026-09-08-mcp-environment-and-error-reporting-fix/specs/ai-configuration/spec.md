# ai-configuration Specification Delta

## MODIFIED Requirements

### Requirement: External MCP client configuration
The application SHALL allow configuring connection parameters for external third-party Model Context Protocol (MCP) servers (supporting stdio command with arguments and environment variables, or SSE endpoint) to discover and execute external tool calls, and SHALL provide authentic connection and tool discovery testing with automatic desktop environment PATH resolution and detailed stderr diagnostic reporting.

#### Scenario: Registering external MCP server
- **WHEN** user provides MCP server identifier, display name, transport type (stdio or SSE), launch command, argument list, and environment variable key-value pairs (such as `FIRECRAWL_API_URL` and `FIRECRAWL_API_KEY`)
- **THEN** the configuration is persisted in `ai_config.json` with all fields preserved and registered in the active runtime MCP service.

#### Scenario: Testing MCP connection and discovering available tools
- **WHEN** user clicks "Test Connection" for an active MCP server in the AI configuration interface
- **THEN** the runtime MCP engine performs an authentic JSON-RPC 2.0 handshake (`initialize`, `notifications/initialized`), executes `tools/list`, displays the count and names of discovered tools, and updates the server status indicator to healthy or surfaces descriptive connection errors.

#### Scenario: Pre-populating Firecrawl MCP template
- **WHEN** user chooses to add the Firecrawl MCP server from the preset templates or configuration manual
- **THEN** the form pre-fills `npx` with args `["-y", "firecrawl-mcp"]` and prompts for `FIRECRAWL_API_URL` and `FIRECRAWL_API_KEY`, allowing one-click verification.

#### Scenario: Automatic desktop environment PATH resolution for stdio MCP processes
- **WHEN** launching a stdio MCP client process from the desktop application bundle
- **THEN** the system automatically inspects and resolves the user's full shell PATH (including NVM, fnm, asdf, volta, Homebrew, and local bin paths), prepending and merging them into the process environment so commands like `npx` and `node` resolve reliably.

#### Scenario: Detailed process failure diagnostics
- **WHEN** a stdio MCP process fails to start, exits with non-zero status code, or writes fatal messages to stderr
- **THEN** the system captures the stderr messages and exit code and surfaces them in the failure notification and `McpServerStatus.lastError` instead of generic interruption errors.
