## MODIFIED Requirements

### Requirement: Interactive AI conversation and web data retrieval dialog
The application SHALL provide an interactive AI chat interface capable of conversing with users, orchestrating MCP tools and resilient multi-backend web search (including Bing and DuckDuckGo fallbacks), and rendering markdown answers with source citations.

#### Scenario: User queries live information requiring web search
- **WHEN** user asks a question in the AI assistant dialog that requires current web data (e.g. searching news or scraping a specific webpage)
- **THEN** the system calls the registered search capability (`web_search` or MCP tool), displays an in-progress tool execution badge, receives structured results, and synthesizes a formatted Markdown response with source links.

#### Scenario: Assistant answer markdown is visually rendered
- **WHEN** an AI assistant reply contains markdown constructs such as headings (`##`), bold or italic emphasis, bullet or numbered lists, inline or fenced code, and blockquotes
- **THEN** the assistant message bubble renders these constructs with distinct visual formatting, and no literal markdown syntax characters are exposed as plain text to the user.
- **AND** the rendered content supports text selection and copying.
- **AND** user-authored messages are rendered as plain text and SHALL NOT be parsed as markdown, so that literal syntax characters typed by the user are preserved exactly as entered.

#### Scenario: User queries standard conversational questions
- **WHEN** user sends general questions or instructions not requiring web search
- **THEN** the AI assistant responds directly via the configured AI text completion slot without invoking external MCP tools.

#### Scenario: Tool execution failure feedback
- **WHEN** all candidate search backends fail or upstream services return errors
- **THEN** the assistant gracefully explains the failure to the user, shows the detailed aggregated diagnostic errors across all attempted endpoints and backends in an expandable badge, and attempts to answer based on available knowledge.

#### Scenario: Search backend fallback and cooldown recovery
- **WHEN** the primary search backend fails due to network or endpoint restrictions
- **THEN** the system automatically cascades to fallback search backends (e.g. DuckDuckGo).
- **AND** if all backends have previously encountered errors and entered cooldown, incoming user searches SHALL bypass cooldown or perform an auto-recovery probe rather than unconditionally rejecting the query.
