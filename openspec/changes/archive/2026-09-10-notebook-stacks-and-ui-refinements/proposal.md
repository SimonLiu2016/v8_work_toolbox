## Why

The notebook tool interface currently displays notebooks in a flat list without honoring hierarchical stacks (notebook groups), lacks automatic workspace maximization on launch, allows side columns to stretch unpredictably, and features an oversized multi-row editor toolbar that crowds the writing space.

Adding stack hierarchy support, fixed navigation widths, compact single-row toolbar styling, and launch-time window maximization creates a refined desktop-native note-taking experience matching modern macOS applications like Evernote and Apple Notes.

## What Changes

- Add hierarchical notebook stack (group) support across the data model, database schema, and UI tree navigation with collapsible/expandable accordion sections.
- Automatically backfill `stack` metadata for existing imported notebooks from the local Evernote SQLite store on startup without requiring a full re-import.
- Fix the leftmost notebook navigation width to 240px and the middle note list width to 320px, letting the right editor pane smoothly occupy all remaining window width.
- Maximize the standalone notebook window on creation to occupy the visible screen frame.
- Refactor the Quill editor toolbar into an elegant, single-row compact toolbar (34px height, 16px icons) with subtle borders and dividers.

## Capabilities

### Modified Capabilities
- `notebook-tool`: Adds requirements for hierarchical notebook stacks navigation and filtering, fixed multi-column layout structure, compact editor toolbar styling, and window launch sizing.

## Impact

- `lib/tools/notebook/note_database.dart`: Adds `stack` column to `notebooks` table and migration.
- `lib/tools/notebook/note_store.dart`: Manages grouped notebook stacks, stack-level note filtering, and automatic stack backfilling.
- `lib/tools/notebook/notebook_page.dart`: Implements collapsible notebook stack trees and sets fixed widths (240px and 320px).
- `lib/tools/notebook/note_editor.dart`: Compacts toolbar configuration to single-row 34px with 16px icons.
- `lib/tools/notebook/evernote_import_service.dart` & `scripts/evernote_import.py`: Persists `stack` from Evernote `ZSTACK`.
- `macos/Runner/MainFlutterWindow.swift`: Maximizes newly created sub-windows to `screen.visibleFrame`.
