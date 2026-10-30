# notebook-storage Delta

## MODIFIED Requirements

### Requirement: Note storage with Quill Delta format
The system SHALL store notes as Quill Delta JSON in SQLite, preserving rich text formatting including headings, bold, italic, code blocks, tables, images, and attachments. A note MAY additionally carry optional structured asset fields (category, purchase date, service period, expiry date) and MAY participate in a generalized note-to-note relationship graph via the `note_links` table; notes without these remain plain notes with no overhead.

#### Scenario: Create a new note
- **WHEN** user creates a new note in a notebook
- **THEN** the system generates a UUID, stores the note with empty Delta content, associates it with the selected notebook, sets created/updated timestamps, and initializes asset fields to empty.

#### Scenario: Auto-save on edit
- **WHEN** user edits note content in the editor
- **THEN** the system auto-saves the Delta JSON to SQLite after a debounce period (e.g. 1 second of inactivity), preserving the full edit history.

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
