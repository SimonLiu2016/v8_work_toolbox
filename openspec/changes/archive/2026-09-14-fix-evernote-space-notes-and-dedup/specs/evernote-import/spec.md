# evernote-import Delta

## MODIFIED Requirements

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

## ADDED Requirements

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
