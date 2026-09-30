## 1. NoteEditor In-Place Live Append

- [x] 1.1 Expose `NoteEditorState` as a public state class
- [x] 1.2 Implement `appendMarkdown(String markdown)` in `NoteEditorState` performing transactional node insertion into `_editorState`
- [x] 1.3 Add post-append focus and view scrolling to the newly added section
- [x] 1.4 Immediately persist appended content to `NoteStore` and invoke `onSaved`

## 2. Integration and Real-time Reflection

- [x] 2.1 Attach `GlobalKey<NoteEditorState>` to `NoteEditor` in `NotebookPage`
- [x] 2.2 Implement `onAppendToActiveNote` in `NotebookPage` delegating to `_editorKey.currentState!.appendMarkdown`
- [x] 2.3 Verify `NotebookQaPanel` dispatches to `onAppendToActiveNote` when target note matches active note
- [x] 2.4 Verify fallback to background SQLite update when target note is not the active note

## 3. Verification and Deployment

- [x] 3.1 Add widget tests verifying `NoteEditorState.appendMarkdown` updates the document live without remounting
- [x] 3.2 Run static analysis (`flutter analyze`) and test suite (`flutter test`)
- [x] 3.3 Re-build and deploy to `/Applications/V8WorkToolbox.app` via `./scripts/deploy_local.sh`

