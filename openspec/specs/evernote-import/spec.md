## Purpose

Enables migration of notes from Evernote (印象笔记) into the local notebook system, including note content, tags, notebook structure, attachments, and timestamps.
## Requirements
### Requirement: Evernote API decryption and import
The system SHALL decrypt AES-encrypted `.notes` files by retrieving the Evernote API token from macOS Keychain and fetching note content via the Evernote API.

#### Scenario: Detect and use stored token
- **WHEN** user initiates an Evernote import
- **THEN** the system reads the Evernote token from macOS Keychain using `security find-generic-password -s "Evernote"`, connects to `app.yinxiang.com`, and lists available notes.

#### Scenario: Fetch encrypted note content via API
- **WHEN** a note in the `.notes` file has AES-encrypted content
- **THEN** the system matches the note by title, fetches the ENML content via the API, and converts it to Markdown.

### Requirement: Note metadata parsing from .notes file
The system SHALL parse the `.notes` XML file to extract note metadata (title, tags, timestamps) and attachments, which are stored unencrypted.

#### Scenario: Parse .notes file structure
- **WHEN** user provides a `.notes` file path
- **THEN** the system parses the XML to extract all note titles, tags, created/updated timestamps, and base64-encoded attachments.

#### Scenario: Extract and save attachments
- **WHEN** a note has resource attachments in the `.notes` file
- **THEN** the system decodes the base64 data and saves each attachment to the local attachments directory.

### Requirement: Batch import with progress
The system SHALL support batch import of all notes with real-time progress reporting.

#### Scenario: Import all notes
- **WHEN** user starts the full import
- **THEN** the system imports all notes sequentially, creating notebooks and tags as needed, and reports progress (current/total, current note title).

#### Scenario: Handle import errors gracefully
- **WHEN** an individual note fails to import (API error, parse failure)
- **THEN** the system logs the error, skips the note, continues with remaining notes, and reports a summary of failures at the end.

### Requirement: Preserve notebook and tag structure
The system SHALL recreate the Evernote notebook hierarchy and tag assignments in the local notebook system. Team-space notes (笔记 stored in Evernote spaces) SHALL be routed to their real underlying notebook via the `ZENTEAMSPACENOTE` join table, with the space name prefixed into the stack hierarchy.

#### Scenario: Map Evernote notebooks
- **WHEN** notes are imported with notebook associations
- **THEN** the system creates local notebooks matching the Evernote notebook names and assigns notes to them.

#### Scenario: Map Evernote tags
- **WHEN** notes are imported with tag assignments
- **THEN** the system creates local tags (if not existing) and links them to the imported notes via the note_tags table.

#### Scenario: Route team-space notes to their real notebook
- **WHEN** a note's notebook is a space-collection notebook (name matches 空间笔记本_<uuid>) and the local database exposes ZENTEAMSPACENOTE
- **THEN** the note is assigned to the real notebook referenced by ZENTEAMSPACENOTE.ZNOTEBOOK, and the space name (ZENTEAMSPACE.ZNAME) is prefixed into the notebook stack (e.g. "专题分享 / 1-工程架构")

#### Scenario: Unroutable space notes fall back to default
- **WHEN** a space-collection note cannot be routed (ZENTEAMSPACENOTE missing or notebook unresolved)
- **THEN** the note falls back to the default notebook and the import summary reports the count

### Requirement: Space-collection notebook identification
The system SHALL identify Evernote space-collection notebooks (names matching the 空间笔记本_<uuid> pattern) during import and SHALL NOT create them as regular notebooks; their notes are routed per the space attribution chain.

#### Scenario: Space-collection notebook skipped
- **WHEN** an import encounters a notebook whose name matches 空间笔记本_<uuid>
- **THEN** no regular notebook is created for it and its notes are routed via the space attribution chain

### Requirement: Duplicate import protection
The system SHALL prevent duplicate note copies across repeated imports by matching on source note GUID (when available) and falling back to same-notebook-same-title matching; a note already imported SHALL be updated in place rather than duplicated.

#### Scenario: Re-import of an already imported note
- **WHEN** an import encounters a note whose source GUID was seen in a previous import (or same title in the same notebook)
- **THEN** the existing local note is updated in place and no duplicate copy is created

### Requirement: Repair mode
The system SHALL offer a repair mode (--repair) that cleans up previously damaged imports: deleting space-collection notebook husks, removing duplicate copies (keeping the newest by updated_at), and re-importing the affected notes under their correct notebooks.

#### Scenario: Repair run cleans duplicates and re-imports
- **WHEN** the user runs the import in repair mode and the database contains a space-collection notebook husk with duplicate copies
- **THEN** the husk notebook and duplicate copies are removed (one newest copy retained per unique note), and the affected notes are re-imported to their real notebooks

#### Scenario: Repair is idempotent
- **WHEN** repair mode runs again after a successful repair
- **THEN** no changes are made (no husk notebooks, no duplicates detected) and the summary reports zero actions

