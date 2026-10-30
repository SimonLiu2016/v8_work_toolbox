## Purpose

Provides a block-based rich text editor using `appflowy_editor` for creating and editing notes with support for native inline tables, code blocks with syntax highlighting, media blocks, Markdown paste conversion, and multi-format export.
## Requirements
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

#### Scenario: Clipboard image pasted into the editor
- **WHEN** user pastes while the clipboard holds a bitmap image or an image URL
- **THEN** the image is stored through the same attachment mechanism as a file-inserted image and appears as an inline image block at the cursor, and the same result is reachable from the toolbar's paste-image control.

#### Scenario: Preset and drag resizing agree on the reference width
- **WHEN** the user first drags an image to its widest and then, on another image, chooses the 100% preset
- **THEN** both images end up the same width, because both paths measure against the editor content area rather than one against the window and the other against an internal pixel value.

#### Scenario: Vector mind map rendering
- **WHEN** a note contains Evernote mind map payload
- **THEN** the editor renders the mind map as an interactive vector block with SVG preview and zoom controls.

### Requirement: Markdown paste conversion
The system SHALL automatically detect and convert Markdown text pasted from the clipboard or fed from the Evernote import pipeline into native rich text blocks.

#### Scenario: Paste Markdown content
- **WHEN** user pastes text containing Markdown syntax (headings, bold, lists, code blocks, tables)
- **THEN** the editor decodes the Markdown into native document blocks (including `TableBlock` and `CodeBlock`), rendering rich text instead of literal Markdown syntax.

#### Scenario: Pasting text never silently does nothing
- **WHEN** the user pastes clipboard text into the editor and the clipboard holds no image in any recognised form
- **THEN** the text reaches the document body, so a paste keystroke always has an observable outcome in the note rather than being consumed without effect.

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
The system SHALL isolate **every light-surface panel in the notebook** from the global dark input decoration theme — including the note editor, the title input, the "问我的笔记" (ask-my-notes) panel, and the asset/credential dialog — and stretch the formatting toolbar across the full width of the editor container. Isolation SHALL be applied at the panel boundary (a light `Theme` wrapper overriding `filled: false` and a transparent fill), not patched field-by-field, so that newly added fields are covered by construction.

#### Scenario: Note title input background
- **WHEN** viewing or editing the note title
- **THEN** the title input field renders with transparent background on white canvas, with no dark gray box artifacts.

#### Scenario: Ask-my-notes panel input legibility
- **WHEN** the user opens the "问我的笔记" panel and types a question
- **THEN** the input field renders on the panel's light background with the global dark fill color suppressed
- **AND** the entered text is legible against that background.

#### Scenario: Asset dialog field legibility
- **WHEN** the user opens the asset/credential dialog and edits the category field
- **THEN** the field renders with the global dark fill color suppressed and its text legible.

#### Scenario: Newly added light-surface panel inherits isolation
- **WHEN** a new light-surface panel is added to the notebook UI
- **THEN** it is wrapped in the shared light-theme boundary rather than relying on each form field to override the global fill
- **AND** its form fields are legible without per-field fixes.

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

### Requirement: Asset fields panel
The editor SHALL provide a panel for editing a note's optional asset fields (category, purchase date, service period, expiry date) and for flagging an attachment as a credential, alongside the rich-text editor. The panel is collapsible and hidden by default for notes that carry no asset data.

#### Scenario: Filling asset fields
- **WHEN** user opens the asset panel for a note and fills category, purchase date, and expiry date
- **THEN** the values are saved to the note's asset fields, and an asset badge with expiry countdown appears on the note in the list.

#### Scenario: Panel hidden for plain notes
- **WHEN** a note has no asset fields filled
- **THEN** the asset panel is collapsed and does not intrude on the editing surface.

#### Scenario: Flagging a credential attachment
- **WHEN** user selects an attachment in the asset panel and marks it as a credential
- **THEN** the attachment is flagged as the credential of record, and is surfaced in AI answers about that asset.

### Requirement: Related notes view in note detail
The editor's note detail view SHALL display the notes related to the current note via the `note_links` table, showing the related note's title and the link's free-text reason, with a click action that navigates to the related note.

#### Scenario: Viewing related notes
- **WHEN** user opens a note that has links to other notes
- **THEN** the detail view lists each related note with its title and the link reason, and clicking one navigates to that note.

#### Scenario: No related notes
- **WHEN** a note has no links
- **THEN** the related-notes section is absent or empty, without placeholder clutter.

### Requirement: Note detail properties consolidated into the metadata bar
The note detail view SHALL present all of a note's property affordances — notebook selector, tags, asset/credential entry, AI tidy-up entry, and related-notes entry — together in the single metadata bar above the formatting toolbar. Property affordances MUST NOT be rendered as separate blocks below the toolbar, so that the editor canvas is not vertically compressed by property UI and a note's attributes are not split across two regions.

#### Scenario: Metadata bar holds all property affordances
- **WHEN** viewing a note in the detail view
- **THEN** the metadata bar contains the notebook selector, the tag list with an add-tag affordance, an asset/credential affordance, and an AI tidy-up affordance
- **AND** no asset panel, tidy-up button, or related-notes block is rendered between the formatting toolbar and the editor canvas.

#### Scenario: Asset affordance opens the full editor
- **WHEN** user activates the asset affordance in the metadata bar
- **THEN** a dialog opens carrying the full asset editing surface (category, purchase date, service period, expiry date, and credential flagging)
- **AND** saving it updates the note and closes the dialog.

#### Scenario: Asset affordance reflects asset state
- **WHEN** a note carries asset data
- **THEN** the asset affordance in the metadata bar reflects that state (e.g. shows the category or the expiry countdown)
- **AND** a note with no asset data shows the bare affordance without a misleading badge.

#### Scenario: Related-notes affordance appears only when links exist
- **WHEN** a note has one or more links
- **THEN** the metadata bar shows a related-notes affordance with the count, and activating it lists the related notes for navigation or removal
- **AND** a note with no links shows no related-notes affordance.

#### Scenario: Editor canvas is not compressed by property UI
- **WHEN** a note carries asset data, tags, and links simultaneously
- **THEN** the editor canvas occupies the remaining vertical space without inline property blocks reducing it
- **AND** the formatting toolbar sits directly above the canvas.

