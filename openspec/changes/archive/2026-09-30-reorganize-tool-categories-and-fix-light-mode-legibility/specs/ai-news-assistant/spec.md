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
- **THEN** the application increments the unread notification badge on the AI assistant tab, displays an in-app alert banner, and sends a macOS system notification with the brief summary.

#### Scenario: Scheduled briefing markdown is visually rendered
- **WHEN** a scheduled retrieval task's summarized digest contains markdown constructs such as headings, emphasis, lists, or inline code
- **THEN** the briefing entry is rendered with the same markdown visual formatting as assistant chat replies, using a single shared rendering component so both surfaces stay visually consistent.

## ADDED Requirements

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
