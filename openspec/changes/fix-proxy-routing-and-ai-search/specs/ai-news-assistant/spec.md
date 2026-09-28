## MODIFIED Requirements

### Requirement: Interactive AI conversation and web data retrieval dialog
The application SHALL provide an interactive AI chat interface capable of conversing with users, orchestrating MCP tools and built-in search/scrape tools for live web search and scraping, and rendering markdown answers with source citations.

#### Scenario: User queries live information requiring web search
- **WHEN** user asks a question in the AI assistant dialog that requires current web data (e.g. searching news or scraping a specific webpage)
- **THEN** the system invokes an appropriate retrieval tool (`web_search`, `web_scrape`, or configured MCP tools such as `firecrawl_search`), displays an in-progress tool execution badge, receives structured results, and synthesizes a formatted Markdown response with source links.

#### Scenario: Assistant answer markdown is visually rendered
- **WHEN** an AI assistant reply contains markdown constructs such as headings (`##`), bold or italic emphasis, bullet or numbered lists, inline or fenced code, and blockquotes
- **THEN** the assistant message bubble renders these constructs with distinct visual formatting, and no literal markdown syntax characters are exposed as plain text to the user.
- **AND** the rendered content supports text selection and copying.
- **AND** user-authored messages are rendered as plain text and SHALL NOT be parsed as markdown, so that literal syntax characters typed by the user are preserved exactly as entered.

#### Scenario: User queries standard conversational questions
- **WHEN** user sends general questions or instructions not requiring web search
- **THEN** the AI assistant responds directly via the configured AI text completion slot without invoking external MCP or built-in search tools.

#### Scenario: Tool execution failure feedback
- **WHEN** an MCP or built-in tool call fails or the upstream service returns an error (such as HTTP 502 Bad Gateway)
- **THEN** the assistant gracefully explains the failure to the user, shows the detailed diagnostic error in an expandable badge, and attempts to answer based on available knowledge.

## ADDED Requirements

### Requirement: Built-in search and scrape fallback without external MCP dependencies
The AI news and retrieval assistant SHALL provide built-in `web_search` and `web_scrape` capabilities that operate independently of external MCP services, allowing queries and web content inspection even when MCP services are unconfigured, offline, or explicitly bypassed by the user.

#### Scenario: Fallback search when MCP is unavailable
- **WHEN** a user requests web information and external MCP tools (like Firecrawl) are offline, unconfigured, or failing
- **THEN** the AI assistant invokes the built-in `web_search` tool through the application's search chain (e.g. Bing / SearXNG) and completes the query successfully without reporting inability to access the web.

#### Scenario: Direct scraping without MCP services
- **WHEN** the user instructs the assistant to inspect or scrape a target URL without using MCP
- **THEN** the assistant uses the built-in `web_scrape` tool to retrieve the page content via the active network client (honoring proxy rules) and synthesizes the answer.
