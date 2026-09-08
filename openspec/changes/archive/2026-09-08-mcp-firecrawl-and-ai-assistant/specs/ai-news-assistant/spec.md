## Purpose

Provides an interactive AI chat assistant capable of real-time web retrieval via external MCP tools, along with scheduled background information retrieval and desktop notifications for fresh news and market intelligence.

## ADDED Requirements

### Requirement: Interactive AI conversation and web data retrieval dialog
The application SHALL provide an interactive AI chat interface capable of conversing with users, orchestrating MCP tools for live web search and scraping, and rendering markdown answers with source citations.

#### Scenario: User queries live information requiring web search
- **WHEN** user asks a question in the AI assistant dialog that requires current web data (e.g. searching news or scraping a specific webpage)
- **THEN** the system calls the registered MCP tool (`firecrawl_search` or `firecrawl_scrape`), displays an in-progress tool execution badge, receives structured results, and synthesizes a formatted Markdown response with source links.

#### Scenario: User queries standard conversational questions
- **WHEN** user sends general questions or instructions not requiring web search
- **THEN** the AI assistant responds directly via the configured AI text completion slot without invoking external MCP tools.

#### Scenario: Tool execution failure feedback
- **WHEN** an MCP tool call fails or the upstream service returns an error (such as HTTP 502 Bad Gateway)
- **THEN** the assistant gracefully explains the failure to the user, shows the detailed diagnostic error in an expandable badge, and attempts to answer based on available knowledge.

### Requirement: Scheduled retrieval tasks and automated news briefing
The application SHALL support configuring scheduled information retrieval tasks that run periodically in the background to fetch, summarize, and alert users about new developments.

#### Scenario: Creating a scheduled news retrieval task
- **WHEN** user configures a new scheduled retrieval task with title, search query, target prompt, and interval (e.g., 30 minutes, 2 hours, 1 day)
- **THEN** the task is saved to persistent local storage and scheduled in the background runtime timer.

#### Scenario: Background task execution and new content detection
- **WHEN** a scheduled task's timer triggers while the application is running
- **THEN** the system executes the retrieval query via MCP search tools, generates a summarized digest, compares content against the previous run's digest, and stores the new briefing entry in history.

#### Scenario: User notification on fresh news
- **WHEN** a scheduled retrieval task finishes and detects newly discovered items
- **THEN** the application increments the unread notification badge on the AI assistant tab, displays an in-app alert banner, and sends a macOS system notification with the brief summary.
