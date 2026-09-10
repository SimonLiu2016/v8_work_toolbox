## 1. Toolbar Unification & Selection Wrapping

- [x] 1.1 In `note_editor.dart`, disable Quill primitive `showCodeBlock: false` and place the custom code block button in the primary toolbar group
- [x] 1.2 Implement smart selection wrapping in `_toggleOrInsertCodeBlock()` to wrap selected text into a code block embed or insert an empty block when collapsed

## 2. Gesture Interception & Focus Severing

- [x] 2.1 Wrap `_NoteCodeBlockWidget` in an opaque gesture detector to prevent clicks from bubbling to outer `_focusEditor()`
- [x] 2.2 Sever Quill focus by calling `_editorFocusNode.unfocus()` when code block enters editing mode to eliminate the dual cursor glitch

## 3. In-Place Editing, Line Numbers & Auto-Persistence

- [x] 3.1 Support single-tap anywhere on code display area to switch into inline edit mode with focused cursor
- [x] 3.2 Add blur listener on `_codeFocusNode` to auto-persist code to Quill embed on losing focus without intermediate rebuilds during typing
- [x] 3.3 Add Escape key handler and header complete action to commit edits and restore syntax-highlighted view
- [x] 3.4 Support Tab key indentation inside code block TextField

## 4. Verification, Build & Deployment

- [x] 4.1 Run analyzer and unit tests to verify zero regressions
- [x] 4.2 Build macOS release binary and update `/Applications/V8WorkToolbox.app` via `ditto`
