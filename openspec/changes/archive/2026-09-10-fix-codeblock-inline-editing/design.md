## Context

See `proposal.md` - Why.

The note editor combines Flutter Quill for rich-text document rendering with custom `EmbedBuilder` widgets for complex blocks (code snippets, images, mind maps). Currently, Quill's document focus listener and outer tap gesture detector conflict with the embedded Flutter `TextField` inside the code block widget, causing dual cursors and input keystrokes escaping to the note body.

## Goals / Non-Goals

**Goals:**
- Unify the code block action into a single smart toolbar button that wraps text selections into code blocks or inserts an auto-focused empty code block.
- Single-tap on any code display area seamlessly switches to in-place edit mode.
- Complete focus isolation: Quill unfocuses and hides its document cursor while editing code, preventing characters or deletes from leaking into the surrounding note.
- Automatic blur and Esc persistence: commit code edits back to the Quill Delta embed without rebuilding or interrupting keystrokes during editing.
- Retain language switching, syntax highlighting, copy, and formatting in view mode.

**Non-Goals:**
- External LSP or deep IDE auto-completion inside note code blocks (out of scope for quick notes).
- Altering the SQLite or Markdown persistence schemas (`code_block` embed payload structure remains 100% backward compatible).

## Decisions

### Decision 1: Single Unified Toolbar Action
- **Choice**: Set `showCodeBlock: false` in `QuillSimpleToolbarConfig` and place a custom `IconButton` in the primary toolbar.
- **Rationale**: Having both a built-in Quill line-attribute code button and a custom embed button confused users and produced inconsistent grey boxes instead of rich cards.
- **Alternatives Considered**: Keeping both buttons with different tooltips — rejected because users naturally expect "code block" to always produce the high-quality syntax block.

### Decision 2: Smart Selection Wrapping
- **Choice**: When `!selection.isCollapsed`, read plain text across the range `[selection.start, selection.end]`, delete the selected text from Quill document, and insert `BlockEmbed('code_block', jsonEncode({'code': selectedText, 'language': 'plaintext'}))`.
- **Rationale**: Directly solves the issue where inserting code blocks dropped an empty placeholder above the user's selected snippet.

### Decision 3: Event Bubble Interception & Focus Severing
- **Choice**:
  1. Wrap `_NoteCodeBlockWidget` root in a `GestureDetector(behavior: HitTestBehavior.opaque, onTap: () {})` to intercept clicks from reaching the outer `_focusEditor()` handler.
  2. In `_enterEditMode()`, call `_editorFocusNode.unfocus()`.
  3. Inside `_NoteCodeBlockWidget`, manage a dedicated `FocusNode _codeFocusNode` and `TextEditingController _textCtrl`.
- **Rationale**: Eliminates the dual cursor glitch and prevents keystrokes from being dispatched to Quill's text input channel.

### Decision 4: In-Place Editing Lifecycle & Blur Persistence
- **Choice**:
  - Single tap on the code view activates edit mode.
  - While editing, code changes stay inside `_textCtrl`. Do NOT invoke `quillController.document.replace()` on every keystroke.
  - When `_codeFocusNode` loses focus (blur), the user presses `Esc`, or clicks the `[✓ 完成]` button in the block header, update the Quill Delta embed payload and return to syntax-highlighted display mode.
- **Rationale**: Avoids tearing and rebuilding the widget tree on every keystroke while ensuring changes are safely saved when navigating away.

## Risks / Trade-offs

- **[Risk] User closes window or switches notes while still actively typing inside a code block** → **Mitigation**: Ensure `_persist()` is also triggered on `dispose()` and when `_NoteCodeBlockWidgetState` unmounts or before note body autosave executes.
- **[Risk] Backspace at offset 0 inside code block deleting the embed** → **Mitigation**: The code block `TextField` consumes its own backspaces; only explicit block delete button or deleting from Quill's outer document context removes the block.
