## Purpose

Provides SQLite-based local storage for notebooks, notes, tags, and attachments with full-text search, supporting CRUD operations and hierarchical notebook organization.

## ADDED Requirements

### Requirement: Note storage with Quill Delta format
The system SHALL store notes as Quill Delta JSON in SQLite, preserving rich text formatting including headings, bold, italic, code blocks, tables, images, and attachments.

#### Scenario: Create a new note
- **WHEN** user creates a new note in a notebook
- **THEN** the system generates a UUID, stores the note with empty Delta content, associates it with the selected notebook, and sets created/updated timestamps.

#### Scenario: Auto-save on edit
- **WHEN** user edits note content in the editor
- **THEN** the system auto-saves the Delta JSON to SQLite after a debounce period (e.g. 1 second of inactivity), preserving the full edit history.

#### Scenario: Soft delete and restore
- **WHEN** user deletes a note
- **THEN** the note is marked as deleted (is_deleted=1) but not removed; user can restore it from trash within 30 days.

### Requirement: Notebook organization
The system SHALL support hierarchical notebooks for organizing notes, with drag-and-drop reordering.

#### Scenario: Create and manage notebooks
- **WHEN** user creates, renames, or deletes a notebook
- **THEN** the operation is persisted to SQLite, and the notebook tree updates immediately.

#### Scenario: Move notes between notebooks
- **WHEN** user drags a note to a different notebook
- **THEN** the note's notebook_id is updated, and the note appears in the new notebook's list.

### Requirement: Tag management
The system SHALL support tags for cross-notebook categorization, with multi-tag assignment per note.

#### Scenario: Assign tags to notes
- **WHEN** user adds or removes tags on a note
- **THEN** the note_tags junction table is updated, and the tag filter reflects the change.

#### Scenario: Filter by tag
- **WHEN** user clicks a tag in the sidebar
- **THEN** the note list shows only notes with that tag, regardless of notebook.

### Requirement: Full-text search
The system SHALL provide full-text search across note titles and content using SQLite FTS5.

#### Scenario: Search notes
- **WHEN** user types a search query in the search bar
- **THEN** the system queries FTS5 and returns matching notes ranked by relevance, with search terms highlighted in results.

### Requirement: Attachment storage
The system SHALL store file attachments associated with notes, saved to the local filesystem.

#### Scenario: Attach a file to a note
- **WHEN** user inserts an image or file into a note
- **THEN** the file is copied to the attachments directory, and a reference is stored in the attachments table linked to the note.
