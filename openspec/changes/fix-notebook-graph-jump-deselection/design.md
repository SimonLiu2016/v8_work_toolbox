## Context

See `proposal.md` for motivation.
When jumping to a note via `KnowledgeGraphView` or `NotebookQaPanel`, `_openNoteById(noteId)` in `notebook_page.dart` previously set `_selectedNote = note` but failed to reconcile the current notebook/tag/search navigation filters. The subsequent call to `_refresh(silent: true)` reloaded `_notes` according to the old filters, excluded the note, and triggered `_selectedNote = null;`, resetting the editor to an empty state.

## Goals / Non-Goals

**Goals:**
- Eliminate the deselection flicker when navigating to a note from the knowledge graph or QA citations.
- Synchronously align the left sidebar navigation (active notebook and stack) to the target note's notebook context.
- Clear conflicting search queries and tag filters upon cross-view navigation so the target note is reliably present in `_notes`.
- Ensure the middle note list and right editor remain in sync with the selected note.

**Non-Goals:**
- Altering the normal behavior of user-initiated notebook switching in the sidebar.
- Redesigning the knowledge graph rendering pipeline or force-directed layout engine.

## Decisions

### Decision 1: Navigation Alignment in `_openNoteById`
- **Decision**: Before triggering `_refresh()`, look up the target note's notebook via `_store.allNotebooks()`.
  - If `note.isDeleted` is true: set `_isTrashSelected = true`, and clear other filters.
  - If `note.notebookId != null`: set `_selectedNotebookId = note.notebookId`, `_selectedStack = nb?.stack`, `_isTrashSelected = false`, and clear `_selectedTagId` and `_searchQuery`.
  - If `note.notebookId == null`: set `_selectedNotebookId = null`, `_selectedStack = null`, `_isTrashSelected = false`, effectively navigating to "全部笔记".
- **Rationale**: Guarantees that the query inside `_refresh()` will include the target note, preventing false deselection and bringing the sidebar into full visual harmony with the editor.

### Decision 2: Post-Refresh Selection Guarantee
- **Decision**: In `_openNoteById`, execute `await _refresh(silent: true);` and then explicitly re-verify and assign `_selectedNote = note;` (or updated note instance) inside `setState()`.
- **Rationale**: Prevents any race condition or state mismatch where `_refresh()` might clear `_selectedNote` due to asynchronous intermediate states.

## Risks / Trade-offs

- **[Risk] Clearing active search query on jump** → Mitigation: This is desired behavior when jumping to an explicit target node from the graph; the user expects to see the note in its home notebook context.
