## Context

See proposal.md and specs/notebook-tool/spec.md. Currently, notebooks are stored without stack grouping metadata, `MainFlutterWindow.swift` hardcodes sub-window size to 1200x750, columns in `notebook_page.dart` use variable widths, and `QuillSimpleToolbar` defaults to multi-row wrapping with large icon buttons.

## Goals / Non-Goals

**Goals:**
- Add `stack` string column to Drift database `notebooks` table with automatic backfill from local Evernote SQLite.
- Group notebooks by `stack` in the sidebar with expandable/collapsible tree navigation.
- Allow clicking a stack header to filter all notes across notebooks in that stack, or clicking an individual notebook.
- Fix sidebar to 240px and notes list to 320px; expand editor to fill remaining space.
- Maximize standalone notebook window on creation to `NSScreen.main?.visibleFrame`.
- Redesign editor toolbar to single-row 34px height with 16px icons.

**Non-Goals:**
- Deep arbitrary multi-level nested notebook trees (Evernote only supports 2 levels: Stack -> Notebook).
- Drag-and-drop reorganization of stacks in this iteration.

## Decisions

### 1. Database Schema & Automatic Backfill
- **Decision**: Add `stack` column to `notebooks` table in `note_database.dart` (`TextColumn get stack => text().nullable()();`).
- **Migration & Backfill**: Since the local SQLite file already exists at `~/Documents/notebook.db`, we will ensure a safe `ALTER TABLE notebooks ADD COLUMN stack TEXT;` execution in `customStatement` if not present. During `NoteStore.init()`, check if Evernote's local SQLite (`LocalNoteStore.sqlite`) exists; if so, read `ZENNOTEBOOK` (`ZNAME`, `ZSTACK`) and update `notebooks.stack` where `stack IS NULL`.
- **Alternatives considered**: Requiring users to re-import notes from scratch. Rejected as it takes too much time and could disrupt existing note states.

### 2. Collapsible Stack Tree Navigation UI
- **Decision**: In `notebook_page.dart`, partition notebooks into `stacks` (map of stack name to list of notebooks) and `unstackedNotebooks`. Each stack group is rendered as a clean collapsible section with `_collapsedStacks` state tracking.
- **State Selection**: Introduce `selectedStack` in `NoteStore`. When a stack is clicked, notes from all notebooks with that stack are displayed. When a specific notebook is selected, only that notebook's notes are displayed.

### 3. Fixed Window Column Layout
- **Decision**:
  - Left column: `SizedBox(width: 240, child: ...)`
  - Middle column: `SizedBox(width: 320, child: ...)`
  - Right column: `Expanded(child: ...)`
- **Rationale**: Eliminates unstable jumping of columns during window resizing and provides an optimal reading and list-scanning layout.

### 4. macOS Sub-Window Maximization
- **Decision**: In `macos/Runner/MainFlutterWindow.swift`, replace `frame.size = NSSize(width: 1200, height: 750)` with `if let screen = NSScreen.main { window.setFrame(screen.visibleFrame, display: true) }`.
- **Rationale**: Maximizing to the visible frame utilizes the entire screen while respecting the macOS menu bar and dock.

### 5. Single-Row Compact Quill Toolbar
- **Decision**: Configure `QuillSimpleToolbarConfig` with `multiRowsDisplay: false`, `toolbarSize: 34`, `buttonOptions` base icon size `16`, and clean bottom divider line.
- **Rationale**: Keeps the editor interface distraction-free, elegant, and native.

## Risks / Trade-offs

- **[Risk]**: Local Evernote SQLite path might differ across machines or app sandbox.
  - **Mitigation**: Detect standard Evernote path (`~/Library/Containers/com.yinxiang.Mac/Data/Library/Application Support/com.yinxiang.Mac/.../localNoteStore/LocalNoteStore.sqlite`) dynamically. If not found, skip backfill gracefully without error.
- **[Risk]**: Single row toolbar might overflow on very narrow windows.
  - **Mitigation**: Single-row mode in Flutter Quill natively supports horizontal mousewheel/drag scrolling with left/right scroll buttons.
