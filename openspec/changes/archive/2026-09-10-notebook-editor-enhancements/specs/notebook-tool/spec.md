## ADDED Requirements

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
The notebook editor SHALL render code snippets with syntax highlighting, language selection, line numbers, one-click copy, and formatting capabilities.

#### Scenario: Syntax highlighting and language switching
- **WHEN** a code block is rendered or edited
- **THEN** syntax tokens are highlighted based on the chosen language, and users can switch programming languages from a dropdown list.

#### Scenario: Line numbers and clipboard copy
- **WHEN** viewing a code snippet
- **THEN** line numbers are displayed along the left gutter, and clicking the copy button copies the code text to the clipboard with visual confirmation.

#### Scenario: Code formatting
- **WHEN** a user clicks the format button on a supported code snippet such as JSON
- **THEN** the code is automatically formatted with consistent indentation.

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
