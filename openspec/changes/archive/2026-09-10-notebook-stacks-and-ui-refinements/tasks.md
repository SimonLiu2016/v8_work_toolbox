## 1. Database Schema and Evernote Stacks Support

- [x] 1.1 Add `stack` column to `notebooks` table in `lib/tools/notebook/note_database.dart` with schema upgrade handling
- [x] 1.2 Update `scripts/evernote_import.py` and `lib/tools/notebook/evernote_import_service.dart` to extract and pass `ZSTACK` as `stack`
- [x] 1.3 Implement automatic stack backfill in `NoteStore` from local Evernote SQLite database

## 2. NoteStore State and Tree Filtering

- [x] 2.1 Add `selectedStack` state and stack-based note filtering to `NoteStore`
- [x] 2.2 Expose grouped notebooks map (stacks and unstacked) in `NoteStore`

## 3. UI Layout and Compact Toolbar

- [x] 3.1 Implement collapsible accordion tree for notebook stacks in `lib/tools/notebook/notebook_page.dart`
- [x] 3.2 Enforce fixed column widths (240px left, 320px middle, expanded right) in `lib/tools/notebook/notebook_page.dart`
- [x] 3.3 Redesign `QuillSimpleToolbar` in `lib/tools/notebook/note_editor.dart` into a single-row 34px compact toolbar with 16px icons

## 4. macOS Sub-Window Maximization

- [x] 4.1 Update `macos/Runner/MainFlutterWindow.swift` to maximize sub-windows to `screen.visibleFrame`

## 5. Verification and Application Build

- [x] 5.1 Run tests and code analysis to verify changes
- [x] 5.2 Build release macOS app and replace `/Applications/V8WorkToolbox.app`
