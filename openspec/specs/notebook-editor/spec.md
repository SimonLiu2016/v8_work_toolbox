## Purpose

Provides a rich text editor based on flutter_quill for creating and editing notes with support for code blocks, tables, images, and Markdown paste conversion.

## Requirements

### Requirement: Rich text editing with Quill Delta
The system SHALL provide a WYSIWYG editor using flutter_quill that stores content as Quill Delta JSON, supporting standard formatting operations.

#### Scenario: Format text
- **WHEN** user applies formatting (bold, italic, underline, strikethrough, headings, lists)
- **THEN** the editor reflects the formatting visually and the Delta JSON records the format attributes.

#### Scenario: Code block with syntax highlighting
- **WHEN** user inserts a code block and selects a language
- **THEN** the code block is rendered with syntax highlighting for the selected language, and the language is stored in the Delta attributes.

#### Scenario: Table editing
- **WHEN** user inserts a table
- **THEN** the editor renders an editable table with add/remove row/column capabilities, stored as a custom embed in Delta.

#### Scenario: Image insertion
- **WHEN** user pastes or drags an image into the editor
- **THEN** the image is saved to the attachments directory, and an image embed is inserted into the Delta content.

### Requirement: Markdown paste conversion
The system SHALL automatically detect and convert Markdown text pasted from the clipboard into rich text Delta format.

#### Scenario: Paste Markdown content
- **WHEN** user pastes text containing Markdown syntax (headings, bold, lists, code blocks, tables)
- **THEN** the editor parses the Markdown and converts it to corresponding Delta ops, rendering rich text instead of literal Markdown syntax.

### Requirement: Export to multiple formats
The system SHALL support exporting the current note to Markdown, HTML, PDF, and plain text formats.

#### Scenario: Export as Markdown
- **WHEN** user clicks "Export → Markdown"
- **THEN** the system converts the Delta content to a .md file and presents a save dialog.

#### Scenario: Export as HTML
- **WHEN** user clicks "Export → HTML"
- **THEN** the system converts the Delta content to a styled .html file with embedded CSS for standalone viewing.

#### Scenario: Export as PDF
- **WHEN** user clicks "Export → PDF"
- **THEN** the system renders the note as HTML and uses macOS PDFKit to generate a .pdf file.

#### Scenario: Export as plain text
- **WHEN** user clicks "Export → Plain Text"
- **THEN** the system strips all formatting and saves only the text content as a .txt file.

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

