## Purpose

Provides Evernote-grade core notebook workflows including accessible note import, checklist todos, note pinning, trash lifecycle management, and smooth non-blocking auto-save.

## ADDED Requirements

### Requirement: Persistent import access
The system SHALL provide persistent, unconditional import entry points for Evernote (.notes and API) and Markdown in the left navigation panel, accessible regardless of whether any note is currently selected or exists.

#### Scenario: Import with zero existing notes
- **WHEN** a user opens a fresh notebook with no notes
- **THEN** the import buttons remain prominently visible and clickable in the navigation panel.

### Requirement: Checklist and rich formatting
The system SHALL support interactive checklist todo items within the rich text editor toolbar and Delta format.

#### Scenario: Insert checklist item
- **WHEN** user clicks the checklist button in the editor toolbar
- **THEN** a checklist todo item with a toggleable checkbox is inserted into the document.

### Requirement: Note pinning and metadata management
The system SHALL allow users to toggle pin status, assign tags, and switch the parent notebook directly from the note header.

#### Scenario: Toggle pin on note
- **WHEN** user clicks the pin icon on a note
- **THEN** the note is pinned to the top of the list and visually badged.

### Requirement: Trash lifecycle and recovery
The system SHALL provide a Trash view in the navigation panel listing soft-deleted notes, with options to restore or permanently delete them.

#### Scenario: Restore deleted note
- **WHEN** user navigates to Trash and clicks restore on a note
- **THEN** the note is restored to the active notes list with is_deleted reset to 0.

### Requirement: Silent debounce auto-save
The system SHALL debounce title and body changes and save them quietly to SQLite without triggering full-screen or list-level loading spinners.

#### Scenario: User types note title and content
- **WHEN** user edits note title or body text
- **THEN** changes are saved within 1 second of inactivity without interrupting focus or flashing the notes list.
