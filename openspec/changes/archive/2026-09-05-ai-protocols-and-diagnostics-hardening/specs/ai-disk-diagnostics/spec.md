## MODIFIED Requirements

### Requirement: Batch diagnostics for low-confidence items
The system SHALL collect metadata for disk candidate items and query `AiService` for safety categorization, prioritizing user-selected items when triggered manually, and preserving error context upon request failure.

#### Scenario: Manual batch diagnostic with user selections
- **WHEN** user manually checks one or more items and triggers AI Batch Diagnostics
- **THEN** the system batches the selected items (up to 8 items) for diagnosis; if no items are checked, it falls back to unanalyzed items.

#### Scenario: Diagnostic failure transparent error reporting
- **WHEN** all or some items in a batch diagnosis fail due to invalid API Key, network error, or rate limits
- **THEN** the failure reasons are captured and displayed to the user via UI notification with specific error details rather than silent failure.

### Requirement: On-demand single item AI analysis
The user interface SHALL provide a dedicated AI inspection button on any file or directory item, allowing interactive explanation of the item's purpose and deletion consequences.

#### Scenario: User queries unknown item
- **WHEN** user clicks "Ask AI" on a specific candidate item
- **THEN** a detailed analysis sheet displays inferred source application, risk evaluation, and human-readable recommendation without transmitting file contents.
