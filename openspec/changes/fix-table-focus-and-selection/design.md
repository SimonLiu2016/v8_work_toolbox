## Context

In `lib/tools/notebook/ui/note_editor.dart`, table embed cells are implemented using Flutter `TextField` inside `_NoteTableWidgetBase`.
Currently, `_enterEditMode` sets `quillController.readOnly = true`, disables `editorFocusNode.canRequestFocus = false`, and invokes `setState` synchronously within a cell's `Listener.onPointerDown`.

This causes three catastrophic failures:
1. Rebuilding the widget tree during pointer down destroys the `RenderEditable` selection gesture recognizer, causing the parent Quill editor's pan recognizer to win the gesture arena and drag-select the entire table embed block.
2. The rapid destruction and recreation of `RenderEditable` disrupts macOS platform text input connection binding, preventing the Delete/Backspace key from modifying cell text.
3. Locking `canRequestFocus = false` and `readOnly = true` prevents Quill editor from receiving focus when clicking outside the table, breaking `TapRegion` outside-tap dismissal and preventing cursor placement in note text.

## Goals / Non-Goals

**Goals:**
- Allow smooth mouse drag-selection of text within table cells.
- Allow Delete/Backspace keys to delete selected or previous characters in table cells.
- Allow single-click outside the table on note text to cleanly unfocus the table, persist changes, and place the cursor in the note body.
- Retain Tab/Shift-Tab cell navigation and Escape to exit.

**Non-Goals:**
- Complete rewrite of the Quill custom embed architecture.
- Multi-cell drag selection across table rows/columns.

## Decisions

### Decision 1: Manage editing state via FocusNode listeners rather than pointer-down `setState`
- **Rationale**: Flutter's `TextField` already contains complete pointer event and drag-selection gesture recognition inside `RenderEditable`. By removing the intrusive `Listener(onPointerDown: ...)` that called `setState`, `TextField`'s gesture recognizer remains intact throughout the entire gesture lifecycle.
- **Implementation**: Attach a listener to each cell's `FocusNode`. When any cell gains focus, update `_isEditing = true` (or simply track active cell). When all cells lose focus, trigger `_exitEditMode` and persist data.

### Decision 2: Remove `readOnly = true` and `canRequestFocus = false` lockout on Quill editor
- **Rationale**: Flutter's focus tree is hierarchical. When a cell's `FocusNode` requests focus, the primary focus naturally shifts to that `TextField`, automatically de-focusing the outer Quill editor. Locking Quill to `readOnly = true` and `canRequestFocus = false` prevents Quill from ever accepting clicks or participating in tap-outside events.
- **Implementation**: Let Flutter's standard focus manager handle focus transitions between Quill and table cells. When clicking note text, Quill acquires focus, the table cells lose focus, and table state is safely persisted.

### Decision 3: Clean key event passthrough for text editing
- **Rationale**: The cell's `FocusNode.onKeyEvent` should only consume navigation shortcuts (Tab, Shift-Tab, Escape).
- **Implementation**: Ensure all text modification keys (Delete, Backspace, Enter/Return when single-line, arrow keys) return `KeyEventResult.ignored` so `EditableText` processes them via standard platform channels.

## Risks / Trade-offs

- **[Risk] Multiple cursors visible simultaneously if Quill doesn't clear selection** → Mitigation: Ensure `quillController.updateSelection(TextSelection.collapsed(offset: -1))` or unfocus when a table cell gains focus, without setting `readOnly = true`.
- **[Risk] Focus transition timing on outside click** → Mitigation: Use both `FocusNode` listener (unfocus on focus loss) and `TapRegion` as fallback to ensure table edits are always persisted when navigating away.
