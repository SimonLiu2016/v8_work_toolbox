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
The notebook editor SHALL render code snippets with syntax highlighting, language selection, line numbers, one-click copy, formatting capabilities, and continuous multi-line stream aggregation.

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

