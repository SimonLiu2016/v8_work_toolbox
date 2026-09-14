## ADDED Requirements

### Requirement: Code block line numbers gutter
The system SHALL display a vertical line numbers gutter to the left of code block content in the notebook editor, updating dynamically with the number of code lines while keeping copied and selected text free of line number prefixes.

#### Scenario: Line numbers match code line count
- **WHEN** user types or pastes multiple lines of code in a code block
- **THEN** the gutter displays sequential integers starting at 1 matching the exact count of lines in the code block.

#### Scenario: Copy code excludes line numbers
- **WHEN** user clicks the "Copy" button or selects text from the code input field
- **THEN** the copied content contains only the pure code text without any line numbers or gutter delimiters.

#### Scenario: Tapping gutter focuses code editor
- **WHEN** user clicks on the line numbers gutter area
- **THEN** the code block input field receives keyboard focus with an active insertion cursor.
