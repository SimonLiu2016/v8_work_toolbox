# ai-news-assistant Specification

## Purpose
Provides an interactive AI chat assistant capable of real-time web retrieval via external MCP tools, along with scheduled background information retrieval and desktop notifications for fresh news and market intelligence.
## Requirements
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

### Requirement: Scheduled retrieval tasks and automated news briefing
The application SHALL support configuring scheduled information retrieval tasks that run periodically in the background to fetch, summarize, and alert users about new developments. Every stored briefing SHALL retain the structured source entries that produced it, so a briefing can be traced back to the pages it came from independently of what the summary text happens to contain.

#### Scenario: Creating a scheduled news retrieval task
- **WHEN** user configures a new scheduled retrieval task with title, search query, target prompt, and interval (e.g., 30 minutes, 2 hours, 1 day)
- **THEN** the task is saved to persistent local storage and scheduled in the background runtime timer.

#### Scenario: Background task execution and new content detection
- **WHEN** a scheduled task's timer triggers while the application is running
- **THEN** the system executes the retrieval query via MCP search tools, generates a summarized digest, compares content against the previous run's digest, and stores the new briefing entry in history together with the source entries (title and URL) of the retrieved results.

#### Scenario: User notification on fresh news
- **WHEN** a scheduled retrieval task finishes and detects newly discovered items
- **THEN** the application increments the unread notification badge on the AI assistant tab, displays an in-app alert banner, and sends a macOS system notification with the brief summary.

#### Scenario: Scheduled briefing markdown is visually rendered
- **WHEN** a scheduled retrieval task's summarized digest contains markdown constructs such as headings, emphasis, lists, or inline code
- **THEN** the briefing entry is rendered with the same markdown visual formatting as assistant chat replies, using a single shared rendering component so both surfaces stay visually consistent.

### Requirement: Briefing sources are clickable to the original page
Each briefing entry SHALL let the user open the original web page of any of its stored sources, and SHALL do so without depending on whether the generated summary restated that source's URL.

#### Scenario: Opening a briefing source
- **WHEN** user activates a source entry listed on a briefing card
- **THEN** the source's URL opens in the system browser, tracking back to the page the briefing summarised.

#### Scenario: Sources present even when the summary omits URLs
- **WHEN** a generated digest does not restate the source URLs
- **THEN** the briefing card still lists the stored source entries, so the ability to reach the original page does not depend on the summariser repeating them.

#### Scenario: Link inside a rendered digest is clickable
- **WHEN** a briefing's digest contains a markdown link
- **THEN** activating it opens the linked page rather than rendering as inert text.

#### Scenario: Historical entries without stored sources
- **WHEN** a briefing entry created before source storage existed is displayed
- **THEN** it renders normally with an empty source list, without error or a missing-data placeholder.
