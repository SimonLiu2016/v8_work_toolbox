## Why

The current code block experience in the notebook editor is fractured and frustrating:
1. Two disjointed code block buttons exist (a plain grey line-attribute button in Quill toolbar vs an insert button at the end), causing confusion.
2. Selecting text and clicking to insert a code block ignores the selection, failing to wrap the code and inserting a placeholder above it instead.
3. Editing inside a code block causes dual blinking cursors (one inside the block and one below it in the main document) due to Quill's outer gesture detector and focus stealing.
4. Keystrokes leak outside the block into the document, while deleting or editing inside the block fails or causes state tears.
5. Entering edit mode requires locating and clicking a tiny 16px icon instead of directly clicking into the code.

This change delivers a cohesive, Typora/Notion-grade code block experience with smart selection wrapping, click-to-edit inline editing, complete focus isolation, and automatic blur persistence.

## What Changes

- **Unified Toolbar Code Block Action**: Remove the primitive Quill `showCodeBlock: false` button from the toolbar and replace it with a first-class Code Block button in the primary formatting group.
- **Smart Selection Wrapping**: When text is selected, clicking the Code Block button extracts the text, removes the original range, and wraps it into a new rich code block embed; when no text is selected, it inserts an empty code block and automatically focuses it.
- **Click-to-Edit & In-Place Cursor**: Clicking anywhere in the code view immediately switches to in-place edit mode with line numbers and standard monospaced text input, without requiring clicking a hidden edit icon.
- **Focus Isolation & Event Guard**: Stop outer `GestureDetector` tap bubbling and unfocus Quill's document input when editing code, completely eliminating dual blinking cursors and character leakage to the document body.
- **Auto-Save on Blur / Esc / Checkmark**: Automatically commit code edits to the Quill document embed upon losing focus, pressing Esc, or clicking the checkmark icon, avoiding intermediate rebuilds during typing.
- **Keyboard Polish**: Support Tab key indentation inside code blocks.

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `notebook-tool`: Update `Professional Code Block Rendering and Tools` requirement to include smart selection wrapping, click-to-edit inline activation, and isolated single-cursor editing.

## Impact

- `lib/tools/notebook/ui/note_editor.dart`: Toolbar layout, selection wrapping handler, outer gesture detection, and `_NoteCodeBlockWidget` interaction and focus management.
- `openspec/specs/notebook-tool/spec.md`: Delta requirement for interactive code block editing.
