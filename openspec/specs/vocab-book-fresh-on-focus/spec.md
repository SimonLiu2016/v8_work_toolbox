# vocab-book-fresh-on-focus Specification

## Purpose
Keeps the vocabulary book honest about words added from elsewhere — the browser companion's popover, the standalone lookup window, or system services — so that switching back to the app shows what was actually added, without a restart or a manual re-entry.
## Requirements
### Requirement: Focus refresh does not start before the view is ready
The focus listener SHALL be attached for the lifetime of the view and SHALL NOT trigger a query before the view's first load has completed.

#### Scenario: Focus before initial load
- **WHEN** the window regains focus before the vocabulary book's first query has finished
- **THEN** no duplicate concurrent query is started, and the initial load's result is what the user sees.

