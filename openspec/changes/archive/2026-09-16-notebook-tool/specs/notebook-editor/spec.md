## Purpose

Provides a rich text editor based on flutter_quill for creating and editing notes with support for code blocks, tables, images, and Markdown paste conversion.

## ADDED Requirements

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
