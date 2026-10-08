## MODIFIED Requirements

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
- **THEN** the application increments the unread notification badge on the AI assistant tab, displays an in-app alert banner, and sends a native macOS desktop notification attributed to V8 Work Toolbox.

#### Scenario: Clicking news notification opens briefing history
- **WHEN** user clicks the news notification or clicks "Show"
- **THEN** the application main window is brought to the foreground, switches the active tool to AI News Assistant, and opens the scheduled tasks drawer showing the news briefing history.

#### Scenario: Scheduled briefing markdown is visually rendered
- **WHEN** a scheduled retrieval task's summarized digest contains markdown constructs such as headings, emphasis, lists, or inline code
- **THEN** the briefing entry is rendered with the same markdown visual formatting as assistant chat replies, using a single shared rendering component so both surfaces stay visually consistent.
