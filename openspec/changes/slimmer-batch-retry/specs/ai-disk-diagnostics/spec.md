## MODIFIED Requirements

### Requirement: Batch diagnostics for low-confidence items
The system SHALL collect metadata for disk candidate items and query `AiService` for safety categorization, prioritizing user-selected items when triggered manually by the user, executing items with configurable concurrency and robust retry logic, handling HTTP 429 errors with exponential backoff across multiple retry attempts, and logging request and response transactions transparently.

#### Scenario: Manual batch diagnostic with user selections
- **WHEN** user manually checks one or more items and triggers AI Batch Diagnostics
- **THEN** the system batches all selected items for diagnosis without a hardcoded upper limit; if no items are checked, it falls back to unanalyzed items.

#### Scenario: Diagnostic failure transparent error reporting
- **WHEN** all or some items in a batch diagnosis fail due to invalid API Key, network error, or rate limits after exhausting all retry attempts
- **THEN** the failure reasons are captured and displayed to the user via UI notification with specific error details rather than silent failure.

#### Scenario: Configurable concurrency with worker pool
- **WHEN** processing multiple items in a batch diagnosis
- **THEN** the system SHALL support a configurable concurrency level (default 1, options: 1/2/3/5); when concurrency is 1, a pacing delay is applied between requests; when concurrency is greater than 1, multiple items are processed in parallel using a worker pool pattern.

#### Scenario: Exponential backoff retry on transient errors
- **WHEN** an individual item diagnosis fails with a retryable error (HTTP 429, timeout, 5xx server error)
- **THEN** the system SHALL retry that item with exponential backoff (base 3s, doubling per attempt, capped at 60s) up to a configurable maximum retry count (default 10), and only mark the item as failed after all retries are exhausted.

#### Scenario: Non-retryable errors skip immediately
- **WHEN** an individual item diagnosis fails with a non-retryable error (HTTP 401, 403, SlotUnavailableException, JSON parse error)
- **THEN** the system SHALL NOT retry that item and immediately record it as failed, continuing with remaining items.

#### Scenario: Configurable batch parameters via UI settings
- **WHEN** user opens the AI batch diagnostics settings panel
- **THEN** the user can configure concurrency (1/2/3/5) and max retry count (3/5/10), and these settings are persisted across sessions.

#### Scenario: Concurrent progress reporting
- **WHEN** batch diagnosis runs with concurrency greater than 1
- **THEN** the progress indicator shows "completed N/M" without naming individual items, since multiple items are processed simultaneously.

#### Scenario: Transparent logging of AI transactions
- **WHEN** any AI request is dispatched or a response is received
- **THEN** structured log events containing the target endpoint, provider, model, prompt summary, HTTP status code, duration, and response preview are printed to the console; retry attempts are logged with attempt number and delay duration.
