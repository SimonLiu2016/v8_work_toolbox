## MODIFIED Requirements

### Requirement: Actionable QA Results: Saving and Appending Notes
The ask-my-notes panel SHALL provide action buttons on generated answer cards enabling users to save the AI response as a new rich-text note or append it directly to the active note. When appending to the currently open note in the editor, the newly appended content SHALL render immediately on the editing canvas without requiring note deselection or switching.

#### Scenario: Saving answer as a new note
- **WHEN** the user clicks the "Save as New Note" button on an AI answer card
- **THEN** the system parses the Markdown response into rich-text document blocks
- **AND** creates a new note in the active notebook titled after the question or summary
- **AND** opens the newly created note in the editor with confirmation feedback.

#### Scenario: Appending answer to current note
- **WHEN** the user clicks the "Append to Note" button on an AI answer card while a note is open
- **THEN** the system parses the response and appends the content blocks to the end of the open note document
- **AND** the live editor canvas immediately reflects and renders the appended blocks in-place
- **AND** the editor scrolls to the appended content and persists the updated note with toast confirmation.
