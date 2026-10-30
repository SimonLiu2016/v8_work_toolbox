## Purpose

Keeps the vocabulary book honest about words added from elsewhere — the browser companion's popover, the standalone lookup window, or system services — so that switching back to the app shows what was actually added, without a restart or a manual re-entry.

## ADDED Requirements

### Requirement: Vocabulary entries added elsewhere become visible on window focus
When the application window regains focus, the vocabulary book view SHALL re-query the store so that entries added by any other entry point are shown.

#### Scenario: Word added from the browser popover appears after switching back
- **WHEN** the user adds a word through the browser companion popover while the app is in the background, then switches back to the app with the vocabulary book page open
- **THEN** the newly added entry is present in the list without the user leaving and re-entering the page or restarting the app.

#### Scenario: Word added from the standalone lookup window appears after switching back
- **WHEN** the user adds a word through the standalone lookup window, then returns focus to the main window with the vocabulary book open
- **THEN** the newly added entry is present in the list.

#### Scenario: No external change means no visible refresh
- **WHEN** the window regains focus and nothing was added elsewhere
- **THEN** the list is not visibly rebuilt — no loading indicator flashes and the scroll position is preserved.

### Requirement: Refresh happens without disturbing the user's current view
An on-focus refresh SHALL NOT discard or reorder what the user is currently looking at, and SHALL NOT alter any selection or filter they have applied.

#### Scenario: Active filter is preserved across a focus refresh
- **WHEN** the user has filtered the vocabulary book (for example to a tag or a mastery range) and the window regains focus
- **THEN** the refresh re-applies the same filter rather than resetting to the unfiltered list.

#### Scenario: Selection is preserved across a focus refresh
- **WHEN** the user has an entry selected and the window regains focus
- **THEN** the selection remains on the same entry after the refresh.

## ADDED Requirements

### Requirement: Focus refresh does not start before the view is ready
The focus listener SHALL be attached for the lifetime of the view and SHALL NOT trigger a query before the view's first load has completed.

#### Scenario: Focus before initial load
- **WHEN** the window regains focus before the vocabulary book's first query has finished
- **THEN** no duplicate concurrent query is started, and the initial load's result is what the user sees.
