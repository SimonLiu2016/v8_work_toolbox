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
