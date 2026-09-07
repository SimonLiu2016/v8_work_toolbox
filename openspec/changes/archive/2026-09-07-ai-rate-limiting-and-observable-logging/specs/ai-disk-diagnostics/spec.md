## MODIFIED Requirements

### Requirement: Batch diagnostics for low-confidence items
The system SHALL collect metadata for disk candidate items and query `AiService` for safety categorization, prioritizing user-selected items when triggered manually by the user, executing items serially with rate-limiting pacing delays, handling HTTP 429 errors with transient backoff rather than permanent slot cooldown, and logging request and response transactions transparently.

#### Scenario: Manual batch diagnostic with user selections
- **WHEN** user manually checks one or more items and triggers AI Batch Diagnostics
- **THEN** the system batches the selected items (up to 8 items) for diagnosis; if no items are checked, it falls back to unanalyzed items.

#### Scenario: Diagnostic failure transparent error reporting
- **WHEN** all or some items in a batch diagnosis fail due to invalid API Key, network error, or rate limits
- **THEN** the failure reasons are captured and displayed to the user via UI notification with specific error details rather than silent failure.

#### Scenario: Rate-limited serial execution with pacing delay
- **WHEN** processing multiple items in a batch diagnosis
- **THEN** the system waits for each request to finish before dispatching the next, and introduces a minimum pacing pause (e.g. 800ms) between requests to prevent triggering provider QPS limits.

#### Scenario: Transient backoff on HTTP 429 without slot freezing
- **WHEN** an AI provider returns an HTTP 429 (Too Many Requests) response during diagnosis
- **THEN** the system pauses for a brief backoff period (e.g. 2000ms) and attempts a retry, without marking the entire provider unhealthy or triggering a 60-second cooldown lockdown.

#### Scenario: Transparent logging of AI transactions
- **WHEN** any AI request is dispatched or a response is received
- **THEN** structured log events containing the target endpoint, provider, model, prompt summary, HTTP status code, duration, and response preview are printed to the console.
