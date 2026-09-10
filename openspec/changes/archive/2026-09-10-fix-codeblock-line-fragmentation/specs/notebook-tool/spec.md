## MODIFIED Requirements

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

## ADDED Requirements

### Requirement: Zero-Dependency Evernote ENML Parsing
The Evernote import pipeline SHALL convert ENML documents into clean Markdown using standard library components without requiring external pip dependencies such as `html2text`, and SHALL extract code block language metadata.

#### Scenario: Standalone conversion under system Python
- **WHEN** the local Evernote import runs using system Python `/usr/bin/python3` without third-party packages installed
- **THEN** notes are converted into clean Markdown without throwing `ModuleNotFoundError` or outputting raw `<!DOCTYPE en-note>` markup.

#### Scenario: Extraction of code block language metadata
- **WHEN** an Evernote note contains a code block with `--en-meta` language specification
- **THEN** the language name is normalized and included in the Markdown code fence so the editor displays correct syntax highlighting.
