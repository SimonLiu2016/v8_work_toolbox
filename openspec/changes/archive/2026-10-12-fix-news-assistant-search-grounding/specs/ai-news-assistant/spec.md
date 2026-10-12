# ai-news-assistant Delta

## MODIFIED Requirements

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
