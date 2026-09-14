## 1. Data Sanitization & Codec

- [x] 1.1 Update `notebook_page.dart` `_createNote` to pass `AppFlowyCodec.documentToJson(Document.blank(withInitialText: true))` as the initial payload.
- [x] 1.2 Update `AppFlowyCodec.parseToDocument` to strictly guard `[`-prefixed content, returning `Document.blank(withInitialText: true)` when empty or corrupted, avoiding fallthrough to Markdown.

## 2. Focus Management & Click-to-Edit

- [x] 2.1 Add `_editorFocusNode` in `NoteEditor` and bind it to `AppFlowyEditor(focusNode: _editorFocusNode)`.
- [x] 2.2 Provide a `footer` and enhance tap targets in `NoteEditor` to request focus and position the caret at the document end.

## 3. Verification & Deployment

- [x] 3.1 Create unit and widget tests in `test/new_note_blank_focus_test.dart` and run all notebook tests.
- [x] 3.2 Run static analysis (`flutter analyze lib/tools/notebook/`) to confirm 0 issues.
- [x] 3.3 Build macOS release binary and deploy to `/Applications/V8WorkToolbox.app` via `ditto`.
