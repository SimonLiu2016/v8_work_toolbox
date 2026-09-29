## ADDED Requirements

### Requirement: Uncaught async failures leave a diagnostic trace
Every window entry point SHALL install a global error handler so that an uncaught exception from an asynchronous operation (for example one started from a button handler) is recorded with a diagnostic message, rather than being silently swallowed.

#### Scenario: Button-initiated async failure is recorded
- **WHEN** an async operation started by a control's callback throws and no code in the call chain catches it
- **THEN** the global handler records the error and its stack
- **AND** the failure appears in the diagnostic log rather than disappearing.

#### Scenario: All window entry points are covered
- **WHEN** the set of window entry points is inspected
- **THEN** each one that calls `runApp` installs the global error handling
- **AND** a window that lacks it is a defect.
