## ADDED Requirements

### Requirement: Target Note Context Binding in Ask-My-Notes
The ask-my-notes QA panel SHALL allow users to bind a specific note as the primary context for questions via a persistent scope capsule bar. When a note is bound, the QA service SHALL supply the entire plain-text content of the targeted note into the LLM context, bypassing short snippet truncation.

#### Scenario: Scope bar displays currently open note by default
- **WHEN** the user opens the ask-my-notes panel while a note is active in the editor
- **THEN** the panel displays a top scope capsule indicating the active note title with a remove button
- **AND** submitted questions default to analyzing that note.

#### Scenario: User unbinds note to return to global library search
- **WHEN** the user clicks the remove button on the active note scope capsule
- **THEN** the scope switches to global library retrieval mode
- **AND** subsequent queries perform full-text retrieval across all notes.

#### Scenario: Targeted note full-text prompt injection
- **WHEN** a question is submitted with a targeted note bound
- **THEN** the QA service retrieves the complete document content of the target note
- **AND** injects it as primary reference context in the prompt without restricting it to 800-character snippet truncation.

### Requirement: At-Mention Note Reference Autocomplete in QA Input
The ask-my-notes input box SHALL support typing `@` to trigger an inline note autocomplete suggestion list. Selecting a note SHALL attach that note as an explicit query target.

#### Scenario: Triggering note mention suggestions
- **WHEN** the user types `@` in the question input field
- **THEN** an overlay menu appears adjacent to the input field displaying notes matching the search term following `@`
- **AND** pressing Up/Down keys or clicking selects a candidate note.

#### Scenario: Confirming note mention from autocomplete
- **WHEN** the user selects a note candidate from the autocomplete overlay
- **THEN** the note is added as a bound target reference for the question
- **AND** the input text cursor is restored with the overlay dismissed.

### Requirement: Tool-Assisted Execution During Targeted Note Analysis
When answering questions against a targeted note, the QA assistant SHALL retain the ability to invoke agent tools (including notebook search, web search, and web scrape) to cross-reference related notes or verify external information.

#### Scenario: Assistant uses tools during targeted note analysis
- **WHEN** the user asks a question about a targeted note that requires external verification or cross-referencing other notes
- **THEN** the assistant executes appropriate tools in the agent loop
- **AND** incorporates both the targeted note content and tool execution results into the final answer.

### Requirement: Actionable QA Results: Saving and Appending Notes
The ask-my-notes panel SHALL provide action buttons on generated answer cards enabling users to save the AI response as a new rich-text note or append it directly to the active note.

#### Scenario: Saving answer as a new note
- **WHEN** the user clicks the "Save as New Note" button on an AI answer card
- **THEN** the system parses the Markdown response into rich-text document blocks
- **AND** creates a new note in the active notebook titled after the question or summary
- **AND** opens the newly created note in the editor with confirmation feedback.

#### Scenario: Appending answer to current note
- **WHEN** the user clicks the "Append to Note" button on an AI answer card while a note is open
- **THEN** the system parses the response and appends the content blocks to the end of the open note document
- **AND** persists the updated note with toast confirmation.
