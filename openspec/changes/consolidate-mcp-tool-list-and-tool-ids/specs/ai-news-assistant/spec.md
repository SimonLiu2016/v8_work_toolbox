## MODIFIED Requirements

### Requirement: Interactive AI conversation and web data retrieval dialog
The application SHALL provide an interactive AI chat interface capable of conversing with users, orchestrating MCP tools for live web search and scraping, and rendering markdown answers with source citations. The dialog SHALL expose a per-tool network proxy toggle reflecting the tool's own proxy channel state. The dialog SHALL NOT provide an entry point for enumerating or inspecting the registered external MCP tools; that inventory belongs to the AI configuration surface.

#### Scenario: User queries live information requiring web search
- **WHEN** user asks a question in the AI assistant dialog that requires current web data (e.g. searching news or scraping a specific webpage)
- **THEN** the system calls the registered MCP tool (`firecrawl_search` or `firecrawl_scrape`), displays an in-progress tool execution badge, receives structured results, and synthesizes a formatted Markdown response with source links.

#### Scenario: Assistant answer markdown is visually rendered
- **WHEN** an AI assistant reply contains markdown constructs such as headings (`##`), bold or italic emphasis, bullet or numbered lists, inline or fenced code, and blockquotes
- **THEN** the assistant message bubble renders these constructs with distinct visual formatting, and no literal markdown syntax characters are exposed as plain text to the user.
- **AND** the rendered content supports text selection and copying.
- **AND** user-authored messages are rendered as plain text and SHALL NOT be parsed as markdown, so that literal syntax characters typed by the user are preserved exactly as entered.

#### Scenario: User queries standard conversational questions
- **WHEN** user sends general questions or instructions not requiring web search
- **THEN** the AI assistant responds directly via the configured AI text completion slot without invoking external MCP tools.

#### Scenario: Tool execution failure feedback
- **WHEN** an MCP tool call fails or the upstream service returns an error (such as HTTP 502 Bad Gateway)
- **THEN** the assistant gracefully explains the failure to the user, shows the detailed diagnostic error in an expandable badge, and attempts to answer based on available knowledge.

#### Scenario: Assistant dialog exposes its own proxy channel toggle
- **WHEN** user views the AI assistant dialog header
- **THEN** a proxy toggle specific to this tool is displayed, reflecting whether this tool's requests are routed through the configured proxy channel.
- **AND** toggling it changes only this tool's proxy routing state, leaving other tools' toggles unaffected.

#### Scenario: No MCP tool inventory entry point in the assistant dialog
- **WHEN** user views the AI assistant dialog header
- **THEN** no control is present for listing or inspecting the registered external MCP tools.
- **AND** the assistant dialog provides no path that duplicates the tool inventory available in the AI configuration tab.
