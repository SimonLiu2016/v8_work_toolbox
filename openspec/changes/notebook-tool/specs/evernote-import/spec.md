## Purpose

Enables migration of notes from Evernote (印象笔记) into the local notebook system, including note content, tags, notebook structure, attachments, and timestamps.

## ADDED Requirements

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
The system SHALL recreate the Evernote notebook hierarchy and tag assignments in the local notebook system.

#### Scenario: Map Evernote notebooks
- **WHEN** notes are imported with notebook associations
- **THEN** the system creates local notebooks matching the Evernote notebook names and assigns notes to them.

#### Scenario: Map Evernote tags
- **WHEN** notes are imported with tag assignments
- **THEN** the system creates local tags (if not existing) and links them to the imported notes via the note_tags table.
