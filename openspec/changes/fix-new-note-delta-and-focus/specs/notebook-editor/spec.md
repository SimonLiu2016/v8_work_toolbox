## ADDED Requirements

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
