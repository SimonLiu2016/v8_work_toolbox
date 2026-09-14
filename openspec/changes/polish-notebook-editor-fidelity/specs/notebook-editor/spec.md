## ADDED Requirements

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
