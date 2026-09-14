## Context

The current `NoteEditor` hosts `flutter_quill`, where non-text content (tables, code blocks, mind maps, images) is encapsulated in custom `BlockEmbed` widgets. In Flutter desktop, multiple active text input fields inside the same widget tree trigger conflicts over the operating system's `TextInputClient`. Because all user notes originate from the Evernote import pipeline (`scripts/evernote_import.py`), which already synthesizes clean standard Markdown, we can eliminate the fragile custom Delta converters and adopt a unified block-based document model via `appflowy_editor`.

## Goals / Non-Goals

**Goals:**
- **Zero-Conflict Table Editing**: Provide native inline table editing where cell clicks, keyboard input, Tab traversal, and column width drag-resizing execute within a single unified focus engine.
- **Strict Feature Parity**: Preserve all existing capabilities:
  - Code blocks with syntax highlighting, language selection, and one-click copy.
  - Interactive image manipulation with resize handles and preset percentage scalers.
  - macOS system clipboard bitmap image pasting via Cmd+V.
  - Evernote vector mind map rendering with SVG zoom and outline cards.
  - High-fidelity PDF export with macOS Arial Unicode CJK font embedding.
  - 800ms auto-save debounce to SQLite via `NoteStore`.
  - Independent single-note subwindow support (`desktop_multi_window`).
- **Direct Markdown Ingestion**: Feed clean Markdown from the Evernote importer directly into AppFlowy's `markdownToDocument`, eliminating hand-rolled AST parsers.

**Non-Goals:**
- **Legacy Quill Delta Migration**: No backward compatibility code is needed for arbitrary historical Delta JSON, as notes are imported and refreshed from Evernote.
- **Mobile Touch Gestures**: Optimization is strictly focused on desktop macOS mouse, trackpad, and keyboard interaction.

## Decisions

### Decision 1: Adopt `appflowy_editor` with Block Tree Architecture
- **Rationale**: `appflowy_editor` models documents as a tree of `Node`s (`TableBlock`, `CodeBlock`, `ImageBlock`, `HeadingBlock`, etc.) governed by a single `EditorState`. This eradicates the root cause of dual blinking cursors, focus stealing, and keystrokes leaking to outer lines.
- **Alternatives Considered**:
  - *Keep `flutter_quill` and implement single-active-cell overlay*: Would require complex custom coordinate hit-testing and event virtualization without gaining modern block features (e.g. column resizing, block handles).
  - *`super_editor`*: High quality, but steeper learning curve, less turnkey table support, and heavier API boilerplate compared to `appflowy_editor`.

### Decision 2: Content Storage and Markdown Bridge
- **Rationale**: `appflowy_editor` provides native `markdownToDocument` and `documentToMarkdown`. The `notes.delta_json` column in SQLite will store the serialized document (either JSON or standard Markdown). The Evernote import service will pass its Markdown directly to `markdownToDocument(markdown)`, mapping image media hashes to local attachment file paths.

### Decision 3: Custom Block Builders for Mind Map and Enhanced Images
- **Rationale**: AppFlowy allows registering custom `BlockComponentBuilder`s:
  - `MindMapBlockComponentBuilder`: Encapsulates our existing `_NoteMindMapWidget` to render SVG vector graphics and JSON hierarchy outlines for `mindmap` blocks.
  - `CustomImageBlockComponentBuilder`: Reuses our existing resize handle overlays and context menu around AppFlowy's image node.

### Decision 4: Keyboard Shortcuts and Image Paste
- **Rationale**: Intercept `Cmd+V` / `Ctrl+V` in AppFlowy's command shortcut pipeline. When the clipboard contains a bitmap image (verified via our existing AppleScript probe), save it to the note's attachment store and insert an image node at the current selection. Otherwise, allow normal text paste.

## Risks / Trade-offs

- **[Risk] Flutter SDK and Dependency Constraints** → **Mitigation**: Verified via `flutter pub add --dry-run appflowy_editor` that `appflowy_editor` cleanly resolves under our Flutter 3.35.2 and Dart 3.9 environment without breaking existing dependencies (`drift`, `pdf`, `printing`, `media_kit`).
- **[Risk] Test Suite Obsolescence** → **Mitigation**: Existing tests tailored to Quill's internal controller will be replaced with clean integration tests verifying AppFlowy's document node mutations, table navigation, and export pipelines.
