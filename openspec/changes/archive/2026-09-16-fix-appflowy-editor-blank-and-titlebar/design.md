## Context

Following the migration to `appflowy_editor`, two critical visual layout issues occurred:
1. `SingleChildScrollView` wrapped `AppFlowyEditor`, which resulted in unbounded vertical constraints and destroyed `DesktopScrollService`'s internal layout computations, rendering a blank canvas.
2. The macOS window titlebar (28px) in single note windows and notebook page panels suffered from missing safe area clearance and background color mismatch with the app's global dark theme.

## Goals / Non-Goals

**Goals:**
- Provide a robust, bounded layout container for `AppFlowyEditor` utilizing `EditorScrollController`.
- Configure `EditorStyle.desktop` with clear contrast, cursor styling, and comfortable horizontal margins.
- Add tap-to-focus on empty canvas padding to ensure intuitive cursor acquisition.
- Unify titlebar backgrounds and top padding across `NotebookPage` and `_SingleNoteWindowApp`.
- Implement `testWidgets` regression tests that pump `NoteEditor` and verify rendering and interaction.

**Non-Goals:**
- Changing database schema or Delta codec rules.
- Re-architecting multi-window IPC.

## Decisions

### 1. Direct Expanded mounting of AppFlowyEditor with EditorScrollController
- **Rationale**: `AppFlowyEditor` requires finite constraints to lay out its block children and manages its own internal viewport via `DesktopScrollService`.
- **Alternative considered**: Setting `shrinkWrap: true` on `AppFlowyEditor`. Discarded because `shrinkWrap` on desktop block editors degrades scrolling performance for long documents and can still conflict with gesture hit-testing.

### 2. Gesture tap-to-focus fallback
- **Rationale**: In Notion/AppFlowy style editors, clicking empty space below the document should place the cursor at the end of the document. Wrapping the canvas in a `GestureDetector` that inspects whether the selection is active and issues a focus transaction provides standard desktop UX.

### 3. Dedicated paper-white Theme Wrapper for Note Editor Windows
- **Rationale**: `V8WorkToolboxApp` uses `AppTheme.darkTheme`. For `_SingleNoteWindowApp` and `NotebookPage` right panel, applying a dedicated theme override with `brightness: Brightness.light`, `scaffoldBackgroundColor: Colors.white`, and top macOS traffic light clearance (28px) guarantees a seamless, native titlebar appearance.

## Risks / Trade-offs

- **[Risk]** Large documents might hit boundary edge cases when auto-scrolling during selection.
  - **Mitigation**: Use `AppFlowyEditor(editorScrollController: _scrollController)` to let the built-in desktop selection service coordinate with the controller.
