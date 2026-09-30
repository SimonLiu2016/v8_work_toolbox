## ADDED Requirements

### Requirement: Discovered MCP tool inventory in the client configuration tab
The 外部 MCP 客户端 configuration tab SHALL present the tools discovered from each configured MCP client, grouped by the client that exposes them, so users can see which external capabilities are available without leaving the configuration surface. A client whose connection has not yet been probed SHALL be shown with an explicit undiscovered state rather than an empty or absent entry.

#### Scenario: Viewing discovered tools after probing a client
- **WHEN** user has run the connection test for an MCP client in the 外部 MCP 客户端 tab
- **THEN** the tab displays that client's discovered tools grouped under the client name, each entry showing the tool name and its description.
- **AND** a client exposing no tools is shown as an empty group rather than being omitted from the display.

#### Scenario: Viewing the tab before any client has been probed
- **WHEN** user opens the 外部 MCP 客户端 tab and no client has been connection-tested in the current session
- **THEN** each configured client appears with an undiscovered placeholder indicating that a connection test is required to reveal its tools.
- **AND** the placeholder points the user at the client's own connection test action.

#### Scenario: Reflecting enablement changes in the tool inventory
- **WHEN** user disables a client, or deletes it, from the 外部 MCP 客户端 tab
- **THEN** the tool inventory for that client is removed or replaced by the undiscovered placeholder accordingly, without listing tools from a disabled or absent client.

## MODIFIED Requirements

### Requirement: External MCP client configuration
The application SHALL allow configuring connection parameters for external third-party Model Context Protocol (MCP) servers (supporting stdio command with arguments and environment variables, or SSE endpoint) to discover and execute external tool calls, and SHALL provide authentic connection and tool discovery testing with automatic desktop environment PATH resolution and detailed stderr diagnostic reporting. The application SHALL persist modifications and deletions of MCP servers, honoring empty client configurations across application restarts without automatically re-injecting deleted presets. The tool inventory discovered by the connection test SHALL remain visible in the configuration tab, and SHALL NOT be truncated to a fixed number of entries in any transient notification.

#### Scenario: Registering external MCP server
- **WHEN** user provides MCP server identifier, display name, transport type (stdio or SSE), launch command, argument list, and environment variable key-value pairs (such as `FIRECRAWL_API_URL` and `FIRECRAWL_API_KEY`)
- **THEN** the configuration is persisted in `ai_config.json` with all fields preserved and registered in the active runtime MCP service.

#### Scenario: Deleting external MCP server and persisting across restarts
- **WHEN** user deletes an MCP server (including the default Firecrawl preset) from the configuration interface
- **THEN** the server is removed from `ai_config.json` and in-memory stores.
- **AND** upon application relaunch or configuration reload, the system SHALL NOT automatically re-add the deleted server or preset, and SHALL preserve the empty list if all servers were deleted.

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
