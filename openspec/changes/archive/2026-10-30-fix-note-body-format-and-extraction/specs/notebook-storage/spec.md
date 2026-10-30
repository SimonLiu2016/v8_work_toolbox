# notebook-storage Delta

## MODIFIED Requirements

### Requirement: Note storage with AppFlowy document JSON
The system SHALL store notes as **AppFlowy document JSON** (`{"document":{"type":"page","children":[...]}}`) in SQLite, preserving rich text formatting including headings, bold, italic, code blocks, tables, images, and attachments. The field is named `deltaJson` for historical reasons but MUST NOT be assumed to hold Quill Delta format. Legacy notes stored as Quill Delta arrays (`[{"insert":...}]`) SHALL remain readable.

#### Scenario: Create a new note
- **WHEN** user creates a new note in a notebook
- **THEN** the system generates a UUID, stores the note with an empty AppFlowy document, associates it with the selected notebook, sets created/updated timestamps, and initializes asset fields to empty.

#### Scenario: Auto-save on edit
- **WHEN** user edits note content in the editor
- **THEN** the system auto-saves the AppFlowy document JSON to SQLite after a debounce period (e.g. 1 second of inactivity), preserving the full edit history.

#### Scenario: Legacy Quill-format note remains readable
- **WHEN** a note stored before the AppFlowy migration (Quill Delta array) is opened
- **THEN** the editor parses and displays it correctly, and the next save writes AppFlowy document JSON.

#### Scenario: Soft delete and restore
- **WHEN** user deletes a note
- **THEN** the note is marked as deleted (is_deleted=1) but not removed; user can restore it from trash within 30 days.

#### Scenario: Marking a note as an asset entry
- **WHEN** user fills any of the asset fields (category, purchase date, service period, expiry date) on a note
- **THEN** those fields are persisted on the note row, and the note is treated as an asset entry for reminder and badge purposes; empty asset fields do not change a note's status.

#### Scenario: Marking an attachment as a credential
- **WHEN** user flags an attachment on a note as a credential
- **THEN** the attachment row stores a credential flag, and the attachment is the credential of record for that asset note.

## ADDED Requirements

### Requirement: Single extraction entry point for note body text
Any path that derives **plain text from a stored note body** SHALL go through `AppFlowyCodec.jsonToPlainText`, which handles both the AppFlowy document format and legacy Quill arrays. Callers MUST NOT use Quill-only parsers (such as `MarkdownConverter.deltaToMarkdown`, which does `jsonDecode(...) as List`) on a stored note body, because they throw on the AppFlowy format and — if the exception is swallowed — silently yield empty text.

#### Scenario: Full-text index covers note bodies, not just titles
- **WHEN** a note is indexed for full-text search
- **THEN** the indexed content includes the note body text extracted via `AppFlowyCodec.jsonToPlainText`, not just the title
- **AND** the indexed content is non-empty for any note that has body text

#### Scenario: Retrieval snippets come from the real body
- **WHEN** the knowledge-base service builds a retrieval fragment for a note
- **THEN** the fragment's snippet derives from the note body via `AppFlowyCodec.jsonToPlainText`
- **AND** a body-only query term (absent from the title) still yields a non-empty snippet

#### Scenario: Extraction failure is not silent
- **WHEN** body text extraction cannot parse the stored content
- **THEN** the failure is logged rather than swallowed with no trace
- **AND** the caller degrades to empty content rather than throwing

#### Scenario: Regression guard for the AppFlowy format
- **WHEN** the test suite runs
- **THEN** a test asserts that a note stored in AppFlowy document JSON yields non-empty extracted text containing its body content, so that a regression to Quill-only parsing fails the suite

### Requirement: Generalized note relationship storage
The system SHALL store note-to-note relationships in a `note_links` table with a source note id, target note id, a relation kind, and an optional free-text reason. The relation kind is a single generalized `related_to` value; the system MUST NOT impose predefined semantic relationship types. Links are bidirectional for visibility purposes but stored with a single source/target pair.

#### Scenario: Storing a link
- **WHEN** a link between two notes is created (by user or confirmed AI suggestion)
- **THEN** a row is written to note_links with source note id, target note id, relation `related_to`, and the free-text reason.

#### Scenario: Querying links for a note
- **WHEN** the system lists links for a note
- **THEN** it returns rows where the note is either source or target, so both endpoints see the relationship.

#### Scenario: Cascade delete on note removal
- **WHEN** a note is permanently deleted
- **THEN** all note_links rows where the note is source or target are deleted.
