## 1. Table Cell Focus & Gesture Refactoring

- [x] 1.1 Remove intrusive `Listener(onPointerDown: ...)` in `_buildCell` and eliminate synchronous `setState` during pointer down events to preserve `TextField` drag-to-select text gestures.
- [x] 1.2 Manage table edit state and persistence via `FocusNode` listeners: activate on cell focus, and persist/unfocus when focus moves away from all cells.
- [x] 1.3 Remove `quillController.readOnly = true` and `editorFocusNode.canRequestFocus = false` locks in `_enterEditMode` so clicking outside on note text allows Quill to cleanly acquire focus and update selection.
- [x] 1.4 Clear or hide Quill document selection when a table cell is focused to prevent ghost/dual cursor display without breaking outer tap hit-testing.

## 2. Keyboard & Input Verification

- [x] 2.1 Verify `FocusNode.onKeyEvent` in `_rebuildCellControllers` cleanly delegates Delete/Backspace, arrow navigation, and editing keys to platform text channels.
- [x] 2.2 Verify Tab/Shift-Tab cell navigation and Escape dismissal continue to work as expected.

## 3. Testing & Verification

- [x] 3.1 Update and write automated Flutter widget tests verifying cell text dragging/selection, Delete key deletion, and outside click focus transitions.
- [x] 3.2 Run all notebook and table test suites to ensure zero regressions across the codebase.
- [x] 3.3 Build macOS release and verify the interaction in the desktop application.

