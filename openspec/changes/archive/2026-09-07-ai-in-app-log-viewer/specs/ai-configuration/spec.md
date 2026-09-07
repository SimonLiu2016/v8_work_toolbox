## ADDED Requirements

### Requirement: In-app real-time AI invocation observation and logging
The application SHALL provide an in-app visual dialog/panel that captures and displays AI requests, responses, warnings, and errors in real-time, allowing users to observe interactions, copy diagnostic details, and clear logs.

#### Scenario: Opening AI log viewer from AI configuration page
- **WHEN** user clicks the "View Invocation Logs" button on the AI infrastructure configuration page
- **THEN** the application displays a dialog showing recent AI invocation log entries with timestamps, provider name, protocol, status code, duration, and payloads.

#### Scenario: Opening AI log viewer from Smart Disk Slimmer page
- **WHEN** user clicks the "AI Log" button adjacent to the "AI Batch Diagnostics" button
- **THEN** the application opens the AI log viewer dialog displaying the latest batch diagnostic requests and responses.

#### Scenario: Real-time update of ongoing requests
- **WHEN** an AI request, response, retry warning, or error occurs while the log viewer dialog is open
- **THEN** the dialog updates reactively to display the new entry without requiring manual reload.

#### Scenario: Copying and clearing logs
- **WHEN** user clicks the copy button in the log viewer
- **THEN** the formatted plain-text log transcript is copied to the system clipboard.
- **WHEN** user clicks the clear button
- **THEN** all retained in-memory log entries are purged and the list view resets to an empty state.
