## MODIFIED Requirements

### Requirement: Block-based rich text editing with AppFlowy Editor
The system SHALL provide a block-based WYSIWYG editor using `appflowy_editor`, supporting native inline tables, code blocks with syntax highlighting, and media blocks under a single unified focus and selection engine. Clipboard images pasted into the editor SHALL become inline image blocks through the same storage and rendering path as images inserted from a file, reachable both by keyboard shortcut and from an explicit toolbar control; the editor's paste command is taken over to make room for image handling, and plain-text pasting behaviour SHALL be preserved unchanged.

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
- **WHEN** user inserts a code block or edits its contents
- **THEN** the editor renders a native `CodeBlock` with language selection, syntax highlighting, line numbers, and a one-click copy button.

#### Scenario: Interactive image manipulation
- **WHEN** user selects an embedded image
- **THEN** the editor displays draggable resize handles, percentage preset scaling (25%, 50%, 75%, 100%, Auto), and a right-click context menu offering copy, cut, and delete actions.

#### Scenario: Vector mind map rendering
- **WHEN** a note contains Evernote mind map payload
- **THEN** the editor renders the mind map as an interactive vector block with SVG preview and zoom controls.

#### Scenario: Clipboard image pasted into the editor
- **WHEN** user pastes while the clipboard holds a bitmap image or an image URL
- **THEN** the image is stored through the same attachment mechanism as a file-inserted image and appears as an inline image block at the cursor, and the same result is reachable from the toolbar's paste-image control.
