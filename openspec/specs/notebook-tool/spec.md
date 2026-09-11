## Purpose

Defines rich-text note embedding safety, image block rendering, and readable text selection contrast for the notebook system.
## Requirements
### Requirement: Note Image and Embed Block Rendering
The notebook editor SHALL render embedded image blocks and unknown embed elements safely without throwing unhandled exceptions or rendering error fallback containers.

#### Scenario: Rendering notes with local image attachments
- **WHEN** a user opens a note containing embedded image references to local file paths
- **THEN** the editor renders the image within an adaptive layout with rounded corners and preserves editor focus and editing capabilities.

#### Scenario: Fallback for missing or unresolvable image files
- **WHEN** a note references an image file path that does not exist on disk
- **THEN** the editor displays an inline placeholder card with an image placeholder icon instead of throwing an unhandled exception.

#### Scenario: Fallback for unrecognized embed types
- **WHEN** a note contains an embed object of an unrecognized type
- **THEN** the editor falls back to a graceful placeholder without interrupting the note rendering or text editing pipeline.

### Requirement: Readable Text Selection Contrast
The notebook editor SHALL render selected text with a translucent highlight color so that highlighted characters remain legible underneath the selection mask.

#### Scenario: User selects text in note body
- **WHEN** a user highlights a segment of text in the note editor
- **THEN** the editor displays a translucent light-blue highlight overlay that keeps the underlying text clearly legible.

#### Scenario: User selects text in note title
- **WHEN** a user highlights text within the note title input field
- **THEN** the selected text remains readable and consistent with the body editor selection style.

### Requirement: Hierarchical Notebook Stack Navigation
The notebook tool SHALL organize notebooks into collapsible stack groups according to their parent stack metadata.

#### Scenario: Displaying collapsible notebook stack groups
- **WHEN** the user opens the notebook navigation pane
- **THEN** notebooks sharing the same stack are grouped under an accordion header showing the stack name and notebook count, with collapse/expand toggle controls.

#### Scenario: Filtering notes by stack or individual notebook
- **WHEN** the user clicks on a notebook stack header
- **THEN** the note list displays all notes belonging to all notebooks within that stack.
- **WHEN** the user clicks on a specific notebook under a stack
- **THEN** the note list displays only notes belonging to that specific notebook.

#### Scenario: Automatic stack backfill on startup
- **WHEN** the notebook database initializes and notebooks lack stack metadata
- **THEN** the system matches existing notebooks against the local Evernote database store and updates their stack values without requiring re-import.

### Requirement: Fixed-Width Column Layout and Launch Sizing
The standalone notebook window SHALL provide consistent, non-stretching column widths for navigation and maximize to the display workspace upon opening.

#### Scenario: Fixed sidebar and note list dimensions
- **WHEN** the notebook window is resized or maximized
- **THEN** the leftmost notebook navigation column remains at a fixed width of 240px, the center note list column remains at a fixed width of 320px, and the right-hand note editor flexibly fills all remaining horizontal space.

#### Scenario: Maximizing notebook sub-window on creation
- **WHEN** the user opens the standalone notebook window
- **THEN** the window is automatically maximized to fill the active screen's visible work area (excluding system dock and menu bar).

### Requirement: Compact Single-Row Editor Toolbar
The rich-text note editor SHALL display a streamlined, single-row compact toolbar to maximize vertical writing canvas space.

#### Scenario: Rendering compact toolbar
- **WHEN** the note editor view is displayed
- **THEN** the toolbar renders in a single horizontal row with a height not exceeding 36px, smaller 16px icons, and subtle divider borders, scrolling horizontally when the window width is constrained.

### Requirement: Window Titlebar Safe Area Clearance
The notebook sidebar header SHALL provide sufficient top clearance so that its title, icon, and actions do not collide with native macOS window traffic light buttons.

#### Scenario: Avoiding native macOS window control buttons
- **WHEN** the notebook sub-window is opened on macOS
- **THEN** the sidebar header content is offset downwards by at least 28px, ensuring the native close, minimize, and zoom buttons sit above the header without visual overlap.

### Requirement: Cohesive Light Toolbar and Editor Theme
The rich-text note editor and its toolbar SHALL present a unified, elegant light theme matching the paper editing surface without dark button backgrounds or contrasting black containers.

#### Scenario: Light paper appearance without dark toolbar backgrounds
- **WHEN** the note editor and its formatting toolbar are rendered
- **THEN** both toolbar buttons, popups, and the editor canvas use consistent light-mode surfaces, subtle borders, and harmonious slate/blue accent highlights.

### Requirement: Mind Map Note Visualization
The notebook system SHALL display Evernote mind map notes with vector fidelity and hierarchical structure.

#### Scenario: Displaying imported mind maps with vector clarity and outline trees
- **WHEN** a user opens a note containing mind map data or embedded SVG graphics
- **THEN** the editor renders the visual vector mind map without distortion and provides access to its structured outline tree.

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

### Requirement: Zero-Dependency Evernote ENML Parsing
The Evernote import pipeline SHALL convert ENML documents into clean Markdown using standard library components without requiring external pip dependencies such as `html2text`, and SHALL extract code block language metadata.

#### Scenario: Standalone conversion under system Python
- **WHEN** the local Evernote import runs using system Python `/usr/bin/python3` without third-party packages installed
- **THEN** notes are converted into clean Markdown without throwing `ModuleNotFoundError` or outputting raw `<!DOCTYPE en-note>` markup.

#### Scenario: Extraction of code block language metadata
- **WHEN** an Evernote note contains a code block with `--en-meta` language specification
- **THEN** the language name is normalized and included in the Markdown code fence so the editor displays correct syntax highlighting.

### Requirement: Interactive Image Selection, Resizing, and Clipboard Operations
The notebook editor SHALL allow users to select embedded images, resize them via drag handles or preset options, cut/copy/delete them via context menus, and paste new images directly from the clipboard.

#### Scenario: Image selection and resize drag handles
- **WHEN** a user clicks an embedded image
- **THEN** a selection border appears with draggable resize handles and size preset buttons (25%, 50%, 75%, 100%, Auto).

#### Scenario: Image context menu operations
- **WHEN** a user right-clicks an image
- **THEN** a context menu offers options to copy, cut, delete, or inspect the image.

#### Scenario: Direct image paste from clipboard
- **WHEN** a user presses Command+V while the clipboard contains image data
- **THEN** the image is saved to the local attachments store and embedded into the note at the current cursor position.

### Requirement: Note List Context Menu Actions
The notebook tool SHALL provide a 10-item context menu upon secondary (right-click) tap on any note card in the middle-column note list.

#### Scenario: Right-click menu display with dynamic states
- **WHEN** a user right-clicks on a note card in the notes list
- **THEN** a macOS-style context menu appears at the exact cursor coordinates containing the 10 standard actions, with "从快捷方式中移除" displayed if `isPinned` is true (otherwise "添加笔记到快捷方式"), and "粉碎笔记" displayed in red text if currently viewing the Trash.

#### Scenario: New note creation from context menu
- **WHEN** a user selects "新建笔记" from the context menu
- **THEN** a new blank note is created in the currently active notebook, selected in the list, and opened in the editor with focus on the title field.

#### Scenario: Open note in standalone window
- **WHEN** a user selects "在新窗口中打开笔记"
- **THEN** an independent desktop sub-window is launched displaying only that note in full-featured view, or brings an existing sub-window for that note to the foreground if already open.

#### Scenario: Middle column reflects edits made in a sub-window
- **WHEN** a note is edited and saved in a standalone sub-window, and the user returns focus to the main window
- **THEN** the middle-column note list refreshes to show the updated title and preview text.

#### Scenario: Toggle note shortcuts pin status
- **WHEN** a user selects "添加笔记到快捷方式" or "从快捷方式中移除"
- **THEN** the note's `isPinned` status is toggled, persisting to the database, sorting the note list with pinned notes at the top, and displaying a toast confirmation.

#### Scenario: Quick task checklist creation in note
- **WHEN** a user selects "创建任务"
- **THEN** an unchecked checklist todo item is appended to the end of the note's content and persisted, with visual toast confirmation.

#### Scenario: Share note options
- **WHEN** a user selects "共享笔记…"
- **THEN** a share modal is displayed providing options to copy Markdown, copy plain text, or generate and save a standalone offline HTML page.

#### Scenario: Export note from context menu
- **WHEN** a user selects "导出笔记…"
- **THEN** the export dialog is opened pre-configured for the selected note, allowing export to PDF, Markdown, HTML, or TXT.

#### Scenario: Save note attachments to folder
- **WHEN** a user selects "将附件保存到文件夹…"
- **THEN** the system scans the note for images and attachment files, prompts the user to select an output directory via native file picker, and copies all attachments to that directory using their original filenames with success feedback.

#### Scenario: Copy note internal deep link
- **WHEN** a user selects "复制笔记链接"
- **THEN** the application deep link (`v8work://notebook/note/{id}`) and markdown link format are copied to the system clipboard with toast feedback.

#### Scenario: Move note to another notebook
- **WHEN** a user selects "移动笔记到…" and chooses a destination notebook from a dialog
- **THEN** the note's notebook association is updated to the destination notebook, refreshing both current and target notebook views.

#### Scenario: Note deletion from context menu
- **WHEN** a user selects "删除笔记"
- **THEN** in active views the note is moved to trash with an Undo toast option, and in trash view a confirmation dialog appears before permanently destroying the note.

### Requirement: CJK Fidelity in PDF Document Export
The notebook export system SHALL render Chinese, Japanese, and Korean (CJK) characters with full typographical fidelity without glyph corruption, square replacement boxes, or question marks when exporting notes to PDF.

#### Scenario: Offline PDF export with system CJK font
- **WHEN** exporting a note containing Chinese text to PDF on macOS
- **THEN** the exporter loads the native macOS system CJK TrueType font (`/System/Library/Fonts/Supplemental/Arial Unicode.ttf`) and renders all characters without requiring network access.

#### Scenario: CJK font applies to every rendered text element
- **WHEN** a note with Chinese titles, headers, paragraphs, bullet lists, and code blocks is exported to PDF
- **THEN** all text elements faithfully preserve Chinese glyphs and styling across multiple pages, including text rendered with per-element inline styles.

#### Scenario: Graceful degradation when no system CJK font exists
- **WHEN** exporting a note to PDF and no local system CJK font can be located
- **THEN** the export still completes using the built-in font fallback without attempting any network access.

