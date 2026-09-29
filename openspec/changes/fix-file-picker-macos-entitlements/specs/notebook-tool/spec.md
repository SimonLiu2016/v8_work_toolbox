## ADDED Requirements

### Requirement: Document import reports selection failures
The document import flow SHALL surface a failure that occurs while opening the file panel or before any file is chosen, through the application's error surface, so that the user receives feedback instead of no visible response.

#### Scenario: File panel fails to open
- **WHEN** the user invokes the import action and opening the file panel raises an error
- **THEN** an error message is shown to the user naming the failure
- **AND** the import button does not appear to do nothing.
