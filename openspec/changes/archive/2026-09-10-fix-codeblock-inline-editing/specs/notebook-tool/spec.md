## MODIFIED Requirements

### Requirement: Professional Code Block Rendering and Tools
The notebook editor SHALL render code snippets with syntax highlighting, language selection, line numbers, one-click copy, formatting capabilities, continuous multi-line stream aggregation, smart selection wrapping, and click-to-edit focus isolation.

#### Scenario: Syntax highlighting and language switching
- **WHEN** a code block is rendered or edited
- **THEN** syntax tokens are highlighted based on the chosen language, and users can switch programming languages from a dropdown list.

#### Scenario: Line numbers and clipboard copy
- **WHEN** viewing a code snippet
- **THEN** line numbers are displayed along the left gutter, and clicking the copy button copies the code text to the clipboard with visual confirmation.

#### Scenario: Code formatting
- **WHEN** a user clicks the format button on a supported code snippet such as JSON
- **THEN** the code is automatically formatted with consistent indentation.

#### Scenario: Multi-line code block aggregation from legacy Delta stream
- **WHEN** opening a note containing consecutive lines with code-block attributes
- **THEN** all consecutive lines are aggregated into a single cohesive code block embed without splitting each line into plain text or generating empty code block cards.

#### Scenario: Healing notes with corrupted empty code embeds
- **WHEN** loading a note with empty code block embeds or initializing the notebook store
- **THEN** the editor and storage service automatically clean up empty code embeds and preserve legitimate code and text content.

#### Scenario: Smart selection wrapping from toolbar
- **WHEN** a user selects text in the note editor and clicks the Code Block toolbar button
- **THEN** the selected text is replaced with a new rich code block embed containing the selected text, and when no text is selected, an empty code block is inserted and immediately focused for editing.

#### Scenario: Click-to-edit inline activation
- **WHEN** a user clicks anywhere on the code display area of a code block
- **THEN** the code block seamlessly switches to an in-place editing state with an active text cursor and keyboard input focus, while the outer document editor cursor is hidden.

#### Scenario: Focus isolation and blur auto-save
- **WHEN** a user edits code inside the code block and subsequently clicks outside the code block or presses Escape
- **THEN** the edited code is committed to the note document embed and the block switches back to syntax-highlighted display mode without emitting stray characters to the surrounding document.
