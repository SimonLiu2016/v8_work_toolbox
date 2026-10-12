# ai-news-assistant Specification

## Purpose
Provides an interactive AI chat assistant capable of real-time web retrieval via external MCP tools, along with scheduled background information retrieval and desktop notifications for fresh news and market intelligence.
## Requirements
### Requirement: Interactive AI conversation and web data retrieval dialog
The application SHALL provide an interactive AI chat interface capable of conversing with users, orchestrating MCP tools for live web search and scraping, and rendering markdown answers with source citations. The dialog SHALL expose a per-tool network proxy toggle reflecting the tool's own proxy channel state. The dialog SHALL NOT provide an entry point for enumerating or inspecting the registered external MCP tools; that inventory belongs to the AI configuration surface.

Retrieved search results SHALL reach the model intact — including the snippet text of each result — so the assistant answers from what was found rather than from an empty shell. The assistant SHALL be given the current date as context, so time-relative questions do not force the model to guess. When retrieved results are clearly unrelated to what the user asked, the system SHALL make that state evident instead of silently feeding unrelated material to the model as if it were the answer's basis.

#### Scenario: User queries live information requiring web search
- **WHEN** user asks a question in the AI assistant dialog that requires current web data (e.g. searching news or scraping a specific webpage)
- **THEN** the system calls the registered MCP tool (`firecrawl_search` or `firecrawl_scrape`), displays an in-progress tool execution badge, receives structured results, and synthesizes a formatted Markdown response with source links.

#### Scenario: Each retrieved result carries its snippet, not only its title
- **WHEN** the search backend returns results whose source markup includes a summary snippet for each entry
- **THEN** the snippet is extracted and carried through to the model alongside the title and link, so the assistant can judge whether a result actually addresses the question.

#### Scenario: Search source markup changes shape
- **WHEN** the search backend renames or extends the markup class that carries a result's snippet
- **THEN** the extraction still recovers the snippet across the variants in use rather than silently dropping it, and a regression test asserts snippets are non-empty against a captured real sample.

#### Scenario: Assistant knows the current date
- **WHEN** the assistant composes a search query for a question that refers to the present day
- **THEN** the current date is available to it as context, so it does not embed a guessed year in the query.

#### Scenario: Retrieved results are unrelated to the question
- **WHEN** the search returns results that do not address what the user asked
- **THEN** the assistant tells the user that the retrieval did not produce relevant material, and either answers from general knowledge while saying so, or explains what it would need — rather than presenting unrelated results as the basis of an answer, and rather than claiming it has no network access at all.

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

#### Scenario: Transient tool failure is retried before surfacing
- **WHEN** an MCP tool call fails due to a transient condition such as a connection reset or timeout
- **THEN** the assistant retries the same call a bounded number of times before marking it as failed
- **AND** the retry does not exceed the tool call's configured timeout budget

#### Scenario: Search backend fallback and cooldown recovery
- **WHEN** the primary search backend fails due to network or endpoint restrictions
- **THEN** the system automatically cascades to fallback search backends (e.g. DuckDuckGo).
- **AND** if all backends have previously encountered errors and entered cooldown, incoming user searches SHALL bypass cooldown or perform an auto-recovery probe rather than unconditionally rejecting the query.

#### Scenario: No MCP tool inventory entry point in the assistant dialog
- **WHEN** user views the AI assistant dialog header
- **THEN** no control is present for listing or inspecting the registered external MCP tools.
- **AND** the assistant dialog provides no path that duplicates the tool inventory available in the AI configuration tab.

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

#### Scenario: User notification on fresh news
- **WHEN** a scheduled retrieval task finishes and detects newly discovered items
- **THEN** the application increments the unread notification badge on the AI assistant tab, displays an in-app alert banner, and sends a native macOS desktop notification attributed to V8 Work Toolbox.

#### Scenario: Clicking news notification opens briefing history
- **WHEN** user clicks the news notification or clicks "Show"
- **THEN** the application main window is brought to the foreground, switches the active tool to AI News Assistant, and opens the scheduled tasks drawer showing the news briefing history.

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

### Requirement: Built-in search and scrape fallback without external MCP dependencies
The AI news and retrieval assistant SHALL provide built-in `web_search` and `web_scrape` capabilities that operate independently of external MCP services, allowing queries and web content inspection even when MCP services are unconfigured, offline, or explicitly bypassed by the user.

#### Scenario: Fallback search when MCP is unavailable
- **WHEN** a user requests web information and external MCP tools (like Firecrawl) are offline, unconfigured, or failing
- **THEN** the AI assistant invokes the built-in `web_search` tool through the application's search chain (e.g. Bing / SearXNG) and completes the query successfully without reporting inability to access the web.

#### Scenario: Direct scraping without MCP services
- **WHEN** the user instructs the assistant to inspect or scrape a target URL without using MCP
- **THEN** the assistant uses the built-in `web_scrape` tool to retrieve the page content via the active network client (honoring proxy rules) and synthesizes the answer.

