# ai-news-assistant Delta

## MODIFIED Requirements

### Requirement: Interactive AI conversation and web data retrieval dialog
The application SHALL provide an interactive AI chat interface capable of conversing with users, orchestrating MCP tools for live web search and scraping, and rendering markdown answers with source citations. A failed tool call SHALL be retried a bounded number of times before being reported to the user, so that transient network disturbances do not produce a single-shot failure.

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

#### Scenario: Transient tool failure is retried before surfacing
- **WHEN** an MCP tool call fails due to a transient condition such as a connection reset or timeout
- **THEN** the assistant retries the same call a bounded number of times before marking it as failed
- **AND** the retry does not exceed the tool call's configured timeout budget

#### Scenario: Tool execution failure feedback
- **WHEN** an MCP tool call fails or the upstream service returns an error (such as HTTP 502 Bad Gateway)
- **THEN** the assistant gracefully explains the failure to the user, shows the detailed diagnostic error in an expandable badge, and attempts to answer based on available knowledge.

### Requirement: Scheduled retrieval tasks and automated news briefing
The application SHALL support configuring scheduled information retrieval tasks that run periodically in the background to fetch, summarize, and alert users about new developments. Retrieval SHALL be performed through the application's built-in web search capability with its pluggable backend chain, so that scheduled tasks remain functional when any single external search service is unavailable. A failed retrieval MUST be reported distinctly from a successful retrieval that found no fresh items, and a failed retrieval MUST NOT consume the task's next execution window.

#### Scenario: Creating a scheduled news retrieval task
- **WHEN** user configures a new scheduled retrieval task with title, search query, target prompt, and interval (e.g., 30 minutes, 2 hours, 1 day)
- **THEN** the task is saved to persistent local storage and scheduled in the background runtime timer.

#### Scenario: Background task execution and new content detection
- **WHEN** a scheduled task's timer triggers while the application is running
- **THEN** the system executes the retrieval query via the built-in web search capability, generates a summarized digest, compares content against the previous run's digest, and stores the new briefing entry in history.

#### Scenario: Retrieval failure is reported distinctly from an empty result
- **WHEN** a scheduled task's retrieval fails because no search backend is reachable or all backends return errors
- **THEN** the task result clearly states that retrieval failed and includes the concrete failure reason of the first failing backend
- **AND** the task MUST NOT display a message implying that the search completed and simply found nothing new
- **AND** the underlying failure detail SHALL NOT be hidden only in developer logs

#### Scenario: Retrieval failure does not consume the execution window
- **WHEN** a scheduled task's retrieval fails
- **THEN** the task's last-run timestamp is not advanced to the failed attempt
- **AND** the task remains eligible to retry at the next scheduler tick rather than waiting out the full configured interval before retrying

#### Scenario: Retrieval succeeds but finds nothing new
- **WHEN** a scheduled task's retrieval succeeds and the resulting digest is identical to the previous run's
- **THEN** the task reports an accurate "no new developments" outcome
- **AND** the task's last-run timestamp IS advanced, since the retrieval itself succeeded

#### Scenario: Task survives external search service outage
- **WHEN** a scheduled task runs while the user's primary external search service is down
- **THEN** the task still returns results or an accurate failure report through backend fallback, without user intervention.

#### Scenario: User notification on fresh news
- **WHEN** a scheduled retrieval task finishes and detects newly discovered items
- **THEN** the application increments the unread notification badge on the AI assistant tab, displays an in-app alert banner, and sends a macOS system notification with the brief summary.

#### Scenario: Scheduled briefing markdown is visually rendered
- **WHEN** a scheduled retrieval task's summarized digest contains markdown constructs such as headings, emphasis, lists, or inline code
- **THEN** the briefing entry is rendered with the same markdown visual formatting as assistant chat replies, using a single shared rendering component so both surfaces stay visually consistent.
