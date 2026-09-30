## Why

When users click the "追加到正文" (Append to Note) button on an AI answer card, the content is persisted to SQLite and `NotebookPage._refresh()` is triggered. However, because the note ID remains the same, `NoteEditor` does not re-initialize its in-memory `Document`, meaning the newly appended content is not rendered on screen until the user switches to a different note and then returns to the current note. In addition, any subsequent editor auto-save might overwrite the appended database record with the older in-memory document state.

## What Changes

- **Live Editor Transactional Append**: Expose an `appendMarkdown` method on `NoteEditorState` that parses the Markdown content into AppFlowy nodes and inserts them directly into the live `_editorState` via a transaction.
- **Immediate Visual Reflection & Scroll**: Ensure the newly appended blocks render immediately on the editing canvas and the editor scrolls to and focuses on the appended content.
- **Seamless QA Panel Integration**: Wire `NotebookPage` to provide `onAppendToActiveNote` to `NotebookQaPanel`, dispatching the live append directly to the active editor when the target note is open.
- **Fail-safe Background Fallback**: Retain direct database persistence when appending to a note that is not currently active in the editor.

## Capabilities

### Modified Capabilities
- `notebook-tool`: Ensure appending QA answers to the currently active note reflects immediately in the open editor canvas without requiring note switching.

## Impact

- `lib/tools/notebook/ui/note_editor.dart`: Expose `NoteEditorState` and implement `appendMarkdown`.
- `lib/tools/notebook/ui/notebook_page.dart`: Maintain a `GlobalKey<NoteEditorState>` and wire `onAppendToActiveNote` to `NotebookQaPanel`.
- `lib/tools/notebook/ui/notebook_qa_panel.dart`: Ensure live append is dispatched to active editor when IDs match.
