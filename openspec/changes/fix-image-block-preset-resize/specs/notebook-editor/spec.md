## MODIFIED Requirements

### Requirement: Block-based rich text editing with AppFlowy Editor
The system SHALL provide a block-based WYSIWYG editor using `appflowy_editor`, supporting native inline tables, code blocks with syntax highlighting, and media blocks under a single unified focus and selection engine. For image blocks specifically, the width applied by the preset percentage controls SHALL be reflected on screen, and presets and drag-resizing SHALL resolve width against the same reference so that the two paths cannot disagree.

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
- **THEN** the editor shows a floating control strip above the image offering percentage presets (25%, 50%, 75%, 100%), left/center/right alignment, copy-path and delete actions
- **AND** choosing a preset visibly changes the rendered image width at once.
- **AND** dragging the image's left or right edge also resizes it, showing a live preview while dragging and committing the width when the drag ends.

#### Scenario: Preset and drag resizing agree on the reference width
- **WHEN** the user first drags an image to its widest and then, on another image, chooses the 100% preset
- **THEN** both images end up the same width, because both paths measure against the editor content area rather than one against the window and the other against an internal pixel value.

#### Scenario: Vector mind map rendering
- **WHEN** a note contains Evernote mind map payload
- **THEN** the editor renders the mind map as an interactive vector block with SVG preview and zoom controls.
