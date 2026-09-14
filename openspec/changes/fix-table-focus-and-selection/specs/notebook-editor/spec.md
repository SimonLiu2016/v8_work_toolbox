## MODIFIED Requirements

### Requirement: Rich text editing with Quill Delta
The system SHALL provide a WYSIWYG editor using flutter_quill that stores content as Quill Delta JSON, supporting standard formatting operations.

#### Scenario: Format text
- **WHEN** user applies formatting (bold, italic, underline, strikethrough, headings, lists)
- **THEN** the editor reflects the formatting visually and the Delta JSON records the format attributes.

#### Scenario: Code block with syntax highlighting
- **WHEN** user inserts a code block and selects a language
- **THEN** the code block is rendered with syntax highlighting for the selected language, and the language is stored in the Delta attributes.

#### Scenario: Table editing
- **WHEN** user inserts or edits a table
- **THEN** the editor renders an editable table with add/remove row/column capabilities, stored as a custom embed in Delta. Individual cells support text editing, text dragging/selection within cells, Delete/Backspace keyboard deletion, and clicking outside the table cleanly dismisses cell editing to resume note text editing.

#### Scenario: Image insertion
- **WHEN** user pastes or drags an image into the editor
- **THEN** the image is saved to the attachments directory, and an image embed is inserted into the Delta content.
