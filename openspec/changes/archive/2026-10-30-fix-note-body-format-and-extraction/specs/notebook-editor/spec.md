# notebook-editor Delta

## MODIFIED Requirements

### Requirement: New note blank initialization without syntax leakage
The system SHALL initialize newly created notes with a clean blank AppFlowy document and safely decode **legacy** empty Quill Delta content (from before the AppFlowy migration) without leaking raw JSON or delimiter strings to the editor view. New notes SHALL be persisted as AppFlowy document JSON, not Quill Delta.

#### Scenario: User creates a new note
- **WHEN** user clicks the create note button
- **THEN** the note editor canvas opens completely blank with no raw JSON text (e.g. `[{"insert":"\n"}]`) or syntax artifacts displayed
- **AND** the note is persisted as an AppFlowy document, not a Quill Delta array.

#### Scenario: User opens an existing note saved with empty Quill Delta
- **WHEN** user selects a note whose stored content is an empty Quill Delta JSON array `[{"insert":"\n"}]` (created before the AppFlowy migration)
- **THEN** the decoder normalizes the content to a blank document without leaking the raw JSON array string into the document body
- **AND** the next save rewrites the note as AppFlowy document JSON.

#### Scenario: Body text extraction uses the format-agnostic entry point
- **WHEN** the editor or any downstream consumer needs the note's plain body text
- **THEN** it uses `AppFlowyCodec.jsonToPlainText`, which handles both AppFlowy documents and legacy Quill arrays
- **AND** it does not use Quill-only parsers on stored note bodies.
