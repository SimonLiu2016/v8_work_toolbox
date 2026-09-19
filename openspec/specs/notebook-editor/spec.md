## Purpose

Provides a block-based rich text editor using `appflowy_editor` for creating and editing notes with support for native inline tables, code blocks with syntax highlighting, media blocks, Markdown paste conversion, and multi-format export.
## Requirements
### Requirement: Block-based rich text editing with AppFlowy Editor
The system SHALL provide a block-based WYSIWYG editor using `appflowy_editor`, supporting native inline tables, code blocks with syntax highlighting, and media blocks under a single unified focus and selection engine.

#### Scenario: Format text
- **WHEN** user applies formatting (bold, italic, underline, strikethrough, headings, lists, quotes)
- **THEN** the editor reflects the formatting visually and updates the corresponding block and inline attributes within the document tree.

#### Scenario: Native inline table editing
- **WHEN** user inserts or edits a table in the note
- **THEN** the editor renders a native `TableBlock` where clicking any cell places the primary focus and cursor directly into that cell without spawning secondary ghost cursors or leaking keystrokes to outer note lines.

#### Scenario: Table navigation and structure modification
- **WHEN** user presses Tab / Shift+Tab in a cell, or clicks row/column modification controls
- **THEN** focus advances seamlessly across cells, and rows/columns can be added or deleted without disrupting document state.

#### Scenario: Code block with syntax highlighting and copy
- **WHEN** user inserts a code block or edits code
- **THEN** the editor renders a native `CodeBlock` with language selection, syntax highlighting, line numbers, and a one-click copy button.

#### Scenario: Interactive image manipulation
- **WHEN** user selects an embedded image
- **THEN** the editor displays draggable resize handles, percentage preset scaling (25%, 50%, 75%, 100%, Auto), and a right-click context menu offering copy, cut, and delete actions.

#### Scenario: Vector mind map rendering
- **WHEN** a note contains Evernote mind map payload
- **THEN** the editor renders the mind map as an interactive vector block with SVG preview and zoom controls.

### Requirement: Markdown paste conversion
The system SHALL automatically detect and convert Markdown text pasted from the clipboard or fed from the Evernote import pipeline into native rich text blocks.

#### Scenario: Paste Markdown content
- **WHEN** user pastes text containing Markdown syntax (headings, bold, lists, code blocks, tables)
- **THEN** the editor decodes the Markdown into native document blocks (including `TableBlock` and `CodeBlock`), rendering rich text instead of literal Markdown syntax.

### Requirement: Export to multiple formats
The system SHALL support exporting the current note to Markdown, HTML, PDF, and plain text formats.

#### Scenario: Export as Markdown
- **WHEN** user clicks "Export → Markdown"
- **THEN** the system serializes the AppFlowy document tree into clean Markdown and presents a save dialog.

#### Scenario: Export as HTML
- **WHEN** user clicks "Export → HTML"
- **THEN** the system converts the note into a styled standalone HTML file with embedded CSS.

#### Scenario: Export as PDF
- **WHEN** user clicks "Export → PDF"
- **THEN** the system renders the note with macOS Arial Unicode CJK font embedding to guarantee Chinese character fidelity without tofu symbols.

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

### Requirement: Standalone editor canvas layout and empty space focus
The notebook editor SHALL mount the AppFlowy editor component inside a bounded layout container with native scrolling and responsive padding, and SHALL ensure that tapping any empty area of the editor canvas focuses the document.

#### Scenario: Editor canvas renders with bounded dimensions
- **WHEN** user opens any note (empty or existing)
- **THEN** the editor body beneath the toolbar renders with full visible height, displays existing content with high contrast, and does not collapse or trigger unbounded layout exceptions.

#### Scenario: Tap on empty canvas focuses editor
- **WHEN** user clicks on any empty area below or around the text in the editor
- **THEN** the editor gains focus, the cursor appears at the appropriate document position, and keyboard inputs are captured immediately.

### Requirement: Seamless window titlebar and header integration
The notebook editor and single-note sub-windows SHALL render top navigation and export bars with background styling and top safe margins that integrate cleanly with the macOS transparent titlebar.

#### Scenario: Unified window header on macOS
- **WHEN** a user views the notebook page or single-note editor window on macOS
- **THEN** the top navigation area provides sufficient top clearance for window control buttons without dark border clipping or background color mismatch.

### Requirement: Local image path decoding with spaces
The system SHALL correctly decode and render local attachment images whose file paths contain spaces (such as the standard macOS `Application Support` directory) without regressing to raw Markdown text.

#### Scenario: Rendering attachment with spaces in path
- **WHEN** note content contains an image pointing to a local path with spaces (e.g. `![image](/path/Application Support/image.png)`)
- **THEN** the system decodes the node into a native image block and renders the image without displaying literal Markdown syntax.

### Requirement: Markdown code block AST normalization and inline editing
The system SHALL parse both `code` and `code_block` node types from Markdown into interactive code blocks that support direct inline editing without requiring a separate edit mode toggle.

#### Scenario: Displaying imported code blocks with syntax highlighting
- **WHEN** a note containing fenced code blocks is opened
- **THEN** the code block is rendered inside a styled dark container with language identification, syntax highlighting, and a one-click copy button.

#### Scenario: Direct inline editing of code block
- **WHEN** user clicks inside a code block
- **THEN** cursor focuses directly within the code block text editor and allows immediate typing and modification.

### Requirement: Table header hierarchy and styling
The system SHALL render table headers with distinct background color and bold text formatting, and render table borders with crisp 1.0px stroke.

#### Scenario: Insert and view formatted table
- **WHEN** a table is inserted or viewed in the editor
- **THEN** the first row (row 0) displays as a distinct header with light slate background and bold text, while table borders use clean 1.0px stroke.

### Requirement: Editor chrome theme isolation and full-width alignment
The system SHALL isolate the note editor and title input from the global dark input decoration theme, and stretch the formatting toolbar across the full width of the editor container.

#### Scenario: Note title input background
- **WHEN** viewing or editing the note title
- **THEN** the title input field renders with transparent background on white canvas, with no dark gray box artifacts.

#### Scenario: Formatting toolbar width alignment
- **WHEN** viewing the note editor in any desktop window size
- **THEN** the formatting toolbar stretches to 100% width of the editor panel, aligning flush with the document canvas edges.

### Requirement: New note blank initialization without syntax leakage
The system SHALL initialize newly created notes with a clean blank document and safely decode legacy empty Quill Delta content without leaking raw JSON or delimiter strings to the editor view.

#### Scenario: User creates a new note
- **WHEN** user clicks the create note button
- **THEN** the note editor canvas opens completely blank with no raw JSON text (e.g. `[{"insert":"\n"}]`) or syntax artifacts displayed.

#### Scenario: User opens an existing note saved with empty Quill Delta
- **WHEN** user selects a note whose stored content is an empty Quill Delta JSON array `[{"insert":"\n"}]`
- **THEN** the decoder normalizes the content to a blank document without leaking the raw JSON array string into the document body.

### Requirement: Blank area click to focus and activate cursor
The editor SHALL activate cursor and keyboard input when clicking anywhere in the editing area, including empty space below the existing document blocks.

#### Scenario: User clicks empty space below text content
- **WHEN** user clicks within the editor viewport below existing text blocks
- **THEN** the editor requests keyboard focus and places the active text insertion cursor at the end of the document.

### Requirement: Custom attachment block in editor

The notebook editor SHALL render a custom attachment block (`AttachmentBlock`) when the document contains an attachment reference, displaying the file name, human-readable file size, and a file-type icon. The block SHALL identify its file by attachment record ID and resolve the file's location from the attachment store rather than from a path cached in the document, so that the block always points at the application-managed copy. The block SHALL provide clickable actions to reveal the file in Finder and to save-as to a user-chosen directory. Multiple attachment blocks MAY coexist in a single note, each independently operable. An "添加附件" button SHALL be present in the editor toolbar, allowing the user to select one or more files to insert as attachment blocks.

#### Scenario: Attachment block renders file metadata

- **WHEN** a note contains one or more attachment references
- **THEN** each attachment renders as a distinct block showing the original filename, formatted file size (e.g. "1.2 MB"), and a type-specific icon

#### Scenario: Attachment block points at the application-managed copy

- **WHEN** a file is added as an attachment and the block is rendered
- **THEN** the block's actions operate on the copy held in the application's attachment storage, not on the user's original source path

#### Scenario: Reveal attachment in Finder

- **WHEN** user clicks the "在访达中显示" action on an attachment block
- **THEN** the system opens Finder with the attachment file selected and revealed

#### Scenario: Save attachment as

- **WHEN** user clicks the "另存为" action on an attachment block
- **THEN** the system presents a save dialog and copies the attachment to the chosen destination

#### Scenario: Add attachment from toolbar

- **WHEN** user clicks the "添加附件" button in the editor toolbar and selects one or more files
- **THEN** each selected file is copied to the note's attachments directory, an attachment record is created, and an attachment block referencing that record is inserted at the current cursor position in the document

#### Scenario: Attachment unavailable after record removal

- **WHEN** an attachment block's referenced record no longer exists
- **THEN** the block renders an explicit unavailable state without offering file actions

