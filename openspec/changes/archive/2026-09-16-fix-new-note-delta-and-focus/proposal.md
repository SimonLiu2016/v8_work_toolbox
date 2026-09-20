## Why

When creating a new note, the initial content was still populated with Quill's legacy `[{"insert":"\n"}]`, which caused `AppFlowyCodec.parseToDocument` to convert it to an empty string, fail the non-empty check, fall through into the Markdown parser, and literally render the raw string `[{"insert":"\n"}]` as text in the editor. Additionally, clicking within the vast blank area below document blocks triggered AppFlowy Editor's `clearSelection()` without requesting focus on the keyboard service, making the editor unresponsive until double-clicking or targeting the exact first text line.

## What Changes

- Initialize new notes with canonical AppFlowy Document JSON (`Document.blank(withInitialText: true)`) in `notebook_page.dart`.
- Enhance `AppFlowyCodec.parseToDocument` to intercept all Quill Delta JSON (`[` prefix): if the converted Markdown is empty or if decoding encounters an error, immediately return `Document.blank(withInitialText: true)` rather than falling through to Markdown parsing.
- Provide a persistent `FocusNode` to `AppFlowyEditor(focusNode: ...)` in `note_editor.dart`.
- Configure `footer` in `AppFlowyEditor` with `IgnoreEditorSelectionGesture` and tap-to-focus handler that places the cursor at the end of document and requests focus on `_editorFocusNode`.
- Add test suite `test/new_note_blank_focus_test.dart` to verify zero raw JSON leakage on new notes and immediate blank-space click focusing.

## Capabilities

### Modified Capabilities
- `notebook-editor`: Ensure empty document rendering without Quill syntax leakage and seamless blank space focus/caret activation.

## Impact

- `lib/tools/notebook/ui/notebook_page.dart`: Updated `_createNote` default content payload.
- `lib/tools/notebook/appflowy_codec.dart`: Robust handling for empty/legacy Quill Deltas without fallthrough.
- `lib/tools/notebook/ui/note_editor.dart`: Integrated editor `FocusNode` and `footer` tap-to-focus mechanism.
- `test/new_note_blank_focus_test.dart`: Regression tests for new note blank canvas and focus responsiveness.
