## MODIFIED Requirements

### Requirement: External MCP client configuration
The application SHALL allow configuring connection parameters for external third-party Model Context Protocol (MCP) servers (supporting stdio command with arguments and environment variables, or SSE endpoint) to discover and execute external tool calls, and SHALL provide authentic connection and tool discovery testing.

#### Scenario: Registering external MCP server
- **WHEN** user provides MCP server identifier, display name, transport type (stdio or SSE), launch command, argument list, and environment variable key-value pairs (such as `FIRECRAWL_API_URL` and `FIRECRAWL_API_KEY`)
- **THEN** the configuration is persisted in `ai_config.json` with all fields preserved and registered in the active runtime MCP service.

#### Scenario: Testing MCP connection and discovering available tools
- **WHEN** user clicks "Test Connection" for an active MCP server in the AI configuration interface
- **THEN** the runtime MCP engine performs an authentic JSON-RPC 2.0 handshake (`initialize`, `notifications/initialized`), executes `tools/list`, displays the count and names of discovered tools, and updates the server status indicator to healthy or surfaces descriptive connection errors.

#### Scenario: Pre-populating Firecrawl MCP template
- **WHEN** user chooses to add the Firecrawl MCP server from the preset templates or configuration manual
- **THEN** the form pre-fills `npx` with args `["-y", "firecrawl-mcp"]` and prompts for `FIRECRAWL_API_URL` and `FIRECRAWL_API_KEY`, allowing one-click verification.
