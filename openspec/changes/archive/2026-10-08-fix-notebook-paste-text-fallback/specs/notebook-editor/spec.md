# notebook-editor Delta

## MODIFIED Requirements

### Requirement: Markdown paste conversion
The system SHALL automatically detect and convert Markdown text pasted from the clipboard or fed from the Evernote import pipeline into native rich text blocks.

#### Scenario: Paste Markdown content
- **WHEN** user pastes text containing Markdown syntax (headings, bold, lists, code blocks, tables)
- **THEN** the editor decodes the Markdown into native document blocks (including `TableBlock` and `CodeBlock`), rendering rich text instead of literal Markdown syntax.

#### Scenario: Pasting text never silently does nothing
- **WHEN** the user pastes clipboard text into the editor and the clipboard holds no image in any recognised form
- **THEN** the text reaches the document body, so a paste keystroke always has an observable outcome in the note rather than being consumed without effect.
