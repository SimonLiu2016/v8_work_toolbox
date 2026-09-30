## Context

See `proposal.md` for motivation.

`NotebookPage` hosts both `NoteEditor` (left/center) and `NotebookQaPanel` (right column). Currently, `NotebookPage` does not pass `onAppendToActiveNote` to `NotebookQaPanel`. Consequently, `NotebookQaPanel` performs a headless background update directly to SQLite (`NoteStore.updateNote`) and invokes `onNoteCreated` (`_refresh(silent: true)`).

However, `NoteEditor` is keyed by `ValueKey(_selectedNote?.id)`. Because the note ID has not changed, Flutter reuses the existing `_NoteEditorState` and only calls `didUpdateWidget`. In `didUpdateWidget`, `NoteEditor` skips re-initialization if `oldWidget.note?.id == widget.note?.id`, meaning the in-memory document never receives the newly appended blocks until the user switches to a different note and back.

## Goals / Non-Goals

**Goals:**
- Enable live, in-place insertion of appended Markdown directly into `NoteEditor`'s active AppFlowy `_editorState`.
- Immediately render appended text and horizontal divider blocks on the editor canvas without flickering, unmounting, or note switching.
- Automatically scroll to and focus on the newly appended section.
- Persist the updated document to SQLite immediately to prevent auto-save desync.

**Non-Goals:**
- Real-time multi-user concurrent operational transform (OT).
- Arbitrary inline block patch merging outside of appending to the document end.

## Decisions

### 1. In-place Transactional Append via `NoteEditorState.appendMarkdown`
- **Rationale**: AppFlowyEditor provides transactional node insertion (`editorState.transaction..insertNode(...)` and `editorState.apply(transaction)`). Inserting nodes directly into `_editorState` updates the view immediately, preserves undo/redo history, and maintains widget continuity.
- **Alternatives considered**:
  - *Include `updatedAt` in `NoteEditor`'s key*: Recreating the entire `NoteEditor` destroys the scroll position, causes visible UI flicker, and loses cursor focus.
  - *Re-read deltaJson in `didUpdateWidget`*: Rebuilding `_editorState` from scratch has the same downsides as recreating the widget. In-place node insertion via transactions is native to AppFlowy.

### 2. Wiring via `GlobalKey<NoteEditorState>`
- Make `NoteEditorState` public.
- In `NotebookPage`, declare `final GlobalKey<NoteEditorState> _editorKey = GlobalKey<NoteEditorState>();`.
- Pass `onAppendToActiveNote` to `NotebookQaPanel`:
  - If `_editorKey.currentState != null && _selectedNote?.id == targetNote.id`, invoke `_editorKey.currentState!.appendMarkdown(markdown)`.
  - If target is a different note (e.g. user selected another note via scope capsule), fallback to background database update as before.

## Risks / Trade-offs

- **[Risk] Conflict with active user typing**:
  → **Mitigation**: `apply(transaction)` executes on Flutter's main thread and atomically updates the node tree. Calling `_save()` immediately flushes the combined document to disk, resetting the debounce timer.
