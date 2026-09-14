## 1. Image Path & Markdown Preprocessing

- [x] 1.1 Support space-containing local image paths in `AppFlowyCodec.parseToDocument` by wrapping unclosed spaced URLs in `<...>` and normalizing image nodes.
- [x] 1.2 Update `MarkdownConverter.deltaToMarkdown` to output CommonMark `<...>` for image paths with spaces.

## 2. Code Block AST Normalization & Direct Inline Editing

- [x] 2.1 Register both `'code'` and `'code_block'` builders in `NoteEditor._initBlockBuilders`.
- [x] 2.2 Refactor `NoteCodeBlockComponentWidget` into an inline-editable, dark IDE-styled container without modal switch.

## 3. Title Field & Toolbar Layout Polish

- [x] 3.1 Isolate `NoteEditor` with local light `ThemeData` and set `filled: false` on the note title `TextField`.
- [x] 3.2 Add `width: double.infinity` to `NoteEditorToolbar` and `crossAxisAlignment: CrossAxisAlignment.stretch` to `NoteEditor`.

## 4. Table Header Hierarchy & Styling

- [x] 4.1 Register `TableCellBlockComponentBuilder` with `colorBuilder` returning `#F8FAFC` for row 0.
- [x] 4.2 Configure `TableStyle` with 1.0px border and bold header cell insertion in `NoteEditorToolbar`.

## 5. Verification & Local Deployment

- [x] 5.1 Run static analysis and widget/unit tests to verify non-breaking behavior.
- [x] 5.2 Build macOS release binary (`flutter build macos --release`) and deploy to `/Applications/V8WorkToolbox.app` via `ditto`.
